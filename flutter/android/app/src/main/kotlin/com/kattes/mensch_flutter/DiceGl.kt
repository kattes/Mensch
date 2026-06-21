package com.kattes.mensch_flutter

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Nativer OpenGL-ES-2-Würfel, der in eine Flutter-SurfaceTexture rendert.
 * Verhalten 1:1 aus der Web-Version (`../../game.js`) portiert: Rounded-Box-
 * Geometrie, Tischebenen-Kamera (1 Welteinheit = 1 px), Roll-/Abprallphysik
 * über die Würfelzone, Endlage-Ablesung. Nötig, weil flame_3d/Impeller auf dem
 * Fire TV (Vulkan 1.0) und flutter_angle auf 32-bit-TVs nicht laufen.
 *
 * Channel "dice_gl":  init(texW,texH,unit)->textureId | roll(energy) | dispose
 *                     <- settled(value)
 */
class DiceGl(
    private val textureRegistry: TextureRegistry,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("dice-gl").apply { start() }
    private val handler = Handler(thread.looper)

    // Zone = Texturgröße (physische Pixel); unit = cssU = boardCss/12.
    private var texW = 512
    private var texH = 512
    private var unit = 40f
    private var ds = 54f

    // ----- EGL -----
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    // ----- GL -----
    private var program = 0
    private var aPos = 0; private var aNor = 0; private var aUv = 0
    private var uMvp = 0; private var uNormal = 0; private var uTex = 0; private var uLight = 0
    private var vbo = 0; private var ibo = 0
    private val faceTex = IntArray(6)
    private var faceIdxCount = 0 // Indizes pro Fläche

    // ----- Physik (Bildschirm-Frame wie game.js; q = [w,x,y,z]) -----
    private var dx = 0f; private var dy = 0f
    private var dvx = 0f; private var dvy = 0f
    private var dz = 0f; private var dvz = 0f; private var dwz = 0f
    private var dq = idleQ()
    private var state = 0 // 0 idle, 1 tumble, 2 settle
    private var settleT = 0f
    private var qFrom = idleQ(); private var qTo = idleQ()
    private var value = 1
    private var animating = false
    private var lastNanos = 0L

    private fun idleQ() = qNorm(qMul(qAxis(1f, 0f, 0f, -0.35f), qAxis(0f, 1f, 0f, 0.5f)))

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                texW = (call.argument<Int>("texW") ?: 512).coerceAtLeast(16)
                texH = (call.argument<Int>("texH") ?: 512).coerceAtLeast(16)
                unit = (call.argument<Double>("unit") ?: 40.0).toFloat()
                ds = unit * 1.35f
                val e = textureRegistry.createSurfaceTexture()
                entry = e
                e.surfaceTexture().setDefaultBufferSize(texW, texH)
                surface = Surface(e.surfaceTexture())
                handler.post { setupGl() }
                result.success(e.id())
            }
            "roll" -> {
                val energy = (call.argument<Double>("energy") ?: 0.5).toFloat()
                handler.post { startRoll(energy) }
                result.success(null)
            }
            "dispose" -> { handler.post { teardownGl() }; result.success(null) }
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------- GL-Setup
    private fun setupGl() {
        val sfc = surface ?: return
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val ver = IntArray(2)
        EGL14.eglInitialize(eglDisplay, ver, 0, ver, 1)
        val cfgs = arrayOfNulls<EGLConfig>(1); val n = IntArray(1)
        EGL14.eglChooseConfig(
            eglDisplay,
            intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_DEPTH_SIZE, 16, EGL14.EGL_NONE,
            ), 0, cfgs, 0, 1, n, 0,
        )
        val cfg = cfgs[0]!!
        eglContext = EGL14.eglCreateContext(
            eglDisplay, cfg, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
        )
        eglSurface = EGL14.eglCreateWindowSurface(
            eglDisplay, cfg, sfc, intArrayOf(EGL14.EGL_NONE), 0,
        )
        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

        buildProgram()
        buildGeometry()
        buildTextures()
        buildCamera()

        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glViewport(0, 0, texW, texH)

        dx = texW / 2f; dy = texH / 2f; dq = idleQ()
        drawFrame()
    }

    private fun buildProgram() {
        val vs = compile(GLES20.GL_VERTEX_SHADER, """
            attribute vec3 aPos; attribute vec3 aNor; attribute vec2 aUv;
            uniform mat4 uMvp; uniform mat3 uNormal;
            varying vec2 vUv; varying vec3 vN;
            void main(){ gl_Position = uMvp*vec4(aPos,1.0); vUv=aUv; vN=normalize(uNormal*aNor); }
        """.trimIndent())
        val fs = compile(GLES20.GL_FRAGMENT_SHADER, """
            precision mediump float;
            varying vec2 vUv; varying vec3 vN;
            uniform sampler2D uTex; uniform vec3 uLight;
            void main(){
              float d = max(dot(normalize(vN), normalize(uLight)), 0.0);
              float l = 0.55 + 0.52*d;
              vec4 c = texture2D(uTex, vUv);
              gl_FragColor = vec4(c.rgb*l, 1.0);
            }
        """.trimIndent())
        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vs); GLES20.glAttachShader(program, fs)
        GLES20.glLinkProgram(program); GLES20.glUseProgram(program)
        aPos = GLES20.glGetAttribLocation(program, "aPos")
        aNor = GLES20.glGetAttribLocation(program, "aNor")
        aUv = GLES20.glGetAttribLocation(program, "aUv")
        uMvp = GLES20.glGetUniformLocation(program, "uMvp")
        uNormal = GLES20.glGetUniformLocation(program, "uNormal")
        uTex = GLES20.glGetUniformLocation(program, "uTex")
        uLight = GLES20.glGetUniformLocation(program, "uLight")
    }

    private fun compile(type: Int, src: String): Int {
        val s = GLES20.glCreateShader(type)
        GLES20.glShaderSource(s, src); GLES20.glCompileShader(s)
        val ok = IntArray(1); GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, ok, 0)
        if (ok[0] == 0) android.util.Log.e("DiceGl", "Shader: ${GLES20.glGetShaderInfoLog(s)}")
        return s
    }

    // Rounded-Box (Einheitswürfel, Radius 0.13): unterteilte Flächen, Vertices
    // auf den Rounded-Body projiziert. 6 Flächen in Reihenfolge +x,-x,+y,-y,+z,-z.
    private fun buildGeometry() {
        val segs = 8
        val r = 0.13f
        val h = 0.5f - r
        val verts = ArrayList<Float>()
        val idx = ArrayList<Short>()
        val per = (segs + 1) * (segs + 1)
        faceIdxCount = segs * segs * 6

        // (u,v) in -0.5..0.5 -> 3D-Punkt je Fläche
        fun point(face: Int, u: Float, v: Float): FloatArray = when (face) {
            0 -> floatArrayOf(0.5f, u, v)   // +x
            1 -> floatArrayOf(-0.5f, u, v)  // -x
            2 -> floatArrayOf(u, 0.5f, v)   // +y
            3 -> floatArrayOf(u, -0.5f, v)  // -y
            4 -> floatArrayOf(u, v, 0.5f)   // +z
            else -> floatArrayOf(u, v, -0.5f) // -z
        }

        for (f in 0 until 6) {
            val base = f * per
            for (j in 0..segs) for (i in 0..segs) {
                val u = i.toFloat() / segs - 0.5f
                val v = j.toFloat() / segs - 0.5f
                val p = point(f, u, v)
                val cx = p[0].coerceIn(-h, h)
                val cy = p[1].coerceIn(-h, h)
                val cz = p[2].coerceIn(-h, h)
                var nx = p[0] - cx; var ny = p[1] - cy; var nz = p[2] - cz
                val l = hypot(hypot(nx, ny), nz).let { if (it < 1e-6f) 1f else it }
                nx /= l; ny /= l; nz /= l
                verts.addAll(listOf(
                    cx + nx * r, cy + ny * r, cz + nz * r, // Position
                    nx, ny, nz,                            // Normale
                    i.toFloat() / segs, j.toFloat() / segs, // UV
                ))
            }
            for (j in 0 until segs) for (i in 0 until segs) {
                val a = (base + j * (segs + 1) + i).toShort()
                val b = (base + j * (segs + 1) + i + 1).toShort()
                val c = (base + (j + 1) * (segs + 1) + i).toShort()
                val d = (base + (j + 1) * (segs + 1) + i + 1).toShort()
                idx.addAll(listOf(a, c, b, b, c, d))
            }
        }

        val va = verts.toFloatArray()
        val ia = ShortArray(idx.size) { idx[it] }
        val vb = ByteBuffer.allocateDirect(va.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        vb.put(va).position(0)
        val ib = ByteBuffer.allocateDirect(ia.size * 2).order(ByteOrder.nativeOrder()).asShortBuffer()
        ib.put(ia).position(0)
        val bufs = IntArray(2); GLES20.glGenBuffers(2, bufs, 0)
        vbo = bufs[0]; ibo = bufs[1]
        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, vbo)
        GLES20.glBufferData(GLES20.GL_ARRAY_BUFFER, va.size * 4, vb, GLES20.GL_STATIC_DRAW)
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, ibo)
        GLES20.glBufferData(GLES20.GL_ELEMENT_ARRAY_BUFFER, ia.size * 2, ib, GLES20.GL_STATIC_DRAW)
    }

    // Flächenwerte in Box-Reihenfolge +x,-x,+y,-y,+z,-z (three-Frame, y gespiegelt).
    private val faceValues = intArrayOf(2, 5, 3, 4, 1, 6)

    private fun buildTextures() {
        GLES20.glGenTextures(6, faceTex, 0)
        for (i in 0 until 6) {
            val bmp = pipBitmap(faceValues[i])
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, faceTex[i])
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
            bmp.recycle()
        }
    }

    // Augen-Textur mit Mulden-Optik (Port aus game.js::pipTexture).
    private fun pipBitmap(v: Int): Bitmap {
        val s = 256
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val cv = Canvas(bmp)
        val bgP = Paint(Paint.ANTI_ALIAS_FLAG)
        bgP.shader = RadialGradient(
            s * 0.35f, s * 0.30f, s * 0.85f,
            intArrayOf(0xFFFFFFFF.toInt(), 0xFFE9E7DC.toInt()), floatArrayOf(0f, 1f),
            Shader.TileMode.CLAMP,
        )
        cv.drawRect(0f, 0f, s.toFloat(), s.toFloat(), bgP)
        val pips = pipGrid(v)
        val pad = s * 0.16f; val cell = (s - 2 * pad) / 3f; val rad = s * 0.066f
        for (i in pips) {
            val cx = pad + (i % 3 + 0.5f) * cell
            val cy = pad + (i / 3 + 0.5f) * cell
            val edgeDark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE; strokeWidth = s * 0.012f; color = 0x4D000000
            }
            cv.drawArc(cx - rad * 1.04f, cy - rad * 1.04f, cx + rad * 1.04f, cy + rad * 1.04f, 171f, 144f, false, edgeDark)
            val pit = Paint(Paint.ANTI_ALIAS_FLAG)
            pit.shader = RadialGradient(
                cx - rad * 0.3f, cy - rad * 0.3f, rad,
                intArrayOf(0xFF000000.toInt(), 0xFF181818.toInt(), 0xFF383838.toInt()),
                floatArrayOf(0f, 0.7f, 1f), Shader.TileMode.CLAMP,
            )
            cv.drawCircle(cx, cy, rad, pit)
        }
        return bmp
    }

    private fun pipGrid(v: Int): IntArray = when (v) {
        1 -> intArrayOf(4)
        2 -> intArrayOf(2, 6)
        3 -> intArrayOf(2, 4, 6)
        4 -> intArrayOf(0, 2, 6, 8)
        5 -> intArrayOf(0, 2, 4, 6, 8)
        else -> intArrayOf(0, 2, 3, 5, 6, 8)
    }

    // -------------------------------------------------------------- Kamera
    private val proj = FloatArray(16)
    private val view = FloatArray(16)
    private val vp = FloatArray(16)

    private fun buildCamera() {
        // fov 30°, 1 Welteinheit = 1 px auf der Tischebene (z=0).
        Matrix.perspectiveM(proj, 0, 30f, texW.toFloat() / texH, 50f, 6000f)
        val camZ = (texH / 2f) / tan(15f * Math.PI.toFloat() / 180f)
        Matrix.setIdentityM(view, 0)
        Matrix.translateM(view, 0, 0f, 0f, -camZ)
        Matrix.multiplyMM(vp, 0, proj, 0, view, 0)
    }

    // -------------------------------------------------------------- Physik
    private fun startRoll(energy: Float) {
        if (state != 0) return
        val e = energy.coerceIn(0f, 1f)
        // Ziel: zufälliger Punkt in der Zone; Tempo aus Energie.
        val tx = ds + Math.random().toFloat() * (texW - 2 * ds)
        val ty = ds + Math.random().toFloat() * (texH - 2 * ds)
        var ddx = tx - dx; var ddy = ty - dy
        val len = hypot(ddx, ddy).let { if (it < 1e-3f) 1f else it }
        val sp = (5.5f + e * 8f) * unit
        dvx = ddx / len * sp; dvy = ddy / len * sp
        dvz = 2.4f * unit
        dwz = (Math.random().toFloat() * 2 - 1) * 4f
        state = 1
        startAnimating()
    }

    private fun startAnimating() {
        if (animating) return
        animating = true; lastNanos = System.nanoTime()
        handler.post(frameRunnable)
    }

    private val frameRunnable = object : Runnable {
        override fun run() { stepAndDraw(); if (animating) handler.postDelayed(this, 16) }
    }

    private fun stepAndDraw() {
        val now = System.nanoTime()
        var dt = (now - lastNanos) / 1e9f
        lastNanos = now
        if (dt > 0.05f) dt = 0.05f
        updateDice(dt)
        drawFrame()
    }

    private fun updateDice(dt: Float) {
        val u = unit
        if (state == 1) {
            dx += dvx * dt; dy += dvy * dt
            val h = ds / 2 + 2; val R = 0.72f
            var bounced = false
            if (dx < h) { dx = h; dvx = abs(dvx) * R; bounced = true }
            if (dx > texW - h) { dx = texW - h; dvx = -abs(dvx) * R; bounced = true }
            if (dy < h) { dy = h; dvy = abs(dvy) * R; bounced = true }
            if (dy > texH - h) { dy = texH - h; dvy = -abs(dvy) * R; bounced = true }

            val speed = hypot(dvx, dvy)
            if (bounced) dvz = max(dvz, min(2.2f * u, speed * 0.25f))
            dz += dvz * dt
            dvz -= 14f * u * dt
            if (dz < 0) { dz = 0f; dvz = -dvz * 0.42f; if (abs(dvz) < 0.3f * u) dvz = 0f }

            val dec = 3.4f * u * dt
            if (speed > dec) { val ff = (speed - dec) / speed; dvx *= ff; dvy *= ff } else { dvx = 0f; dvy = 0f }

            if (speed > 1f) {
                val ang = (speed / (ds / 2)) * dt
                dq = qNorm(qMul(qAxis(-dvy / speed, dvx / speed, 0f, ang), dq))
            }
            if (abs(dwz) > 0.05f) {
                dq = qNorm(qMul(qAxis(0f, 0f, 1f, dwz * dt), dq))
                dwz *= exp(-1.8f * dt)
            }
            if (speed < 0.5f * u && dz <= 0.01f) settleDice()
        } else if (state == 2) {
            settleT += dt
            val k = min(1f, settleT / 0.32f)
            val e = 1f - (1f - k) * (1f - k) * (1f - k)
            dq = qSlerp(qFrom, qTo, e)
            if (k >= 1f) {
                dq = qTo; state = 0; animating = false
                val vv = value
                mainHandler.post { channel.invokeMethod("settled", vv) }
            }
        }
    }

    private fun settleDice() {
        state = 2; dvx = 0f; dvy = 0f; dz = 0f; dvz = 0f; settleT = 0f
        value = topFace(dq)
        val nrm = qRotate(dq, FACE_NORMALS[value]!!)
        val cx = nrm[1]; val cy = -nrm[0]
        val s = hypot(cx, cy)
        val ang = kotlin.math.atan2(s, nrm[2])
        val A = if (s > 1e-6f) qAxis(cx / s, cy / s, 0f, ang) else floatArrayOf(1f, 0f, 0f, 0f)
        qFrom = dq; qTo = qNorm(qMul(A, dq))
    }

    private fun topFace(q: FloatArray): Int {
        var best = 1; var bestDot = -2f
        for (v in 1..6) {
            val n = qRotate(q, FACE_NORMALS[v]!!)
            if (n[2] > bestDot) { bestDot = n[2]; best = v }
        }
        return best
    }

    // -------------------------------------------------------------- Render
    private val model = FloatArray(16)
    private val rotM = FloatArray(16)
    private val mvp = FloatArray(16)
    private val normalM = FloatArray(9)

    private fun drawFrame() {
        if (eglSurface == EGL14.EGL_NO_SURFACE) return
        GLES20.glClearColor(0f, 0f, 0f, 0f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        GLES20.glUseProgram(program)

        // Spiegelung Bildschirm-Frame (y runter) -> three/GL-Frame (y rauf):
        // three-Quaternion (x,y,z,w) = (-q[1], q[2], -q[3], q[0]).
        quatXyzwToMatrix(-dq[1], dq[2], -dq[3], dq[0], rotM)
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, dx - texW / 2f, texH / 2f - dy, dz)
        Matrix.multiplyMM(model, 0, model, 0, rotM, 0)
        Matrix.scaleM(model, 0, ds, ds, ds)
        Matrix.multiplyMM(mvp, 0, vp, 0, model, 0)
        normalM[0] = rotM[0]; normalM[1] = rotM[1]; normalM[2] = rotM[2]
        normalM[3] = rotM[4]; normalM[4] = rotM[5]; normalM[5] = rotM[6]
        normalM[6] = rotM[8]; normalM[7] = rotM[9]; normalM[8] = rotM[10]

        GLES20.glUniformMatrix4fv(uMvp, 1, false, mvp, 0)
        GLES20.glUniformMatrix3fv(uNormal, 1, false, normalM, 0)
        // Sonnenrichtung wie game.js (-350,500,790), normiert.
        GLES20.glUniform3f(uLight, -0.346f, 0.495f, 0.797f)

        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, vbo)
        val st = 8 * 4
        GLES20.glEnableVertexAttribArray(aPos); GLES20.glVertexAttribPointer(aPos, 3, GLES20.GL_FLOAT, false, st, 0)
        GLES20.glEnableVertexAttribArray(aNor); GLES20.glVertexAttribPointer(aNor, 3, GLES20.GL_FLOAT, false, st, 12)
        GLES20.glEnableVertexAttribArray(aUv); GLES20.glVertexAttribPointer(aUv, 2, GLES20.GL_FLOAT, false, st, 24)
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, ibo)

        for (f in 0 until 6) {
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, faceTex[f])
            GLES20.glUniform1i(uTex, 0)
            GLES20.glDrawElements(GLES20.GL_TRIANGLES, faceIdxCount, GLES20.GL_UNSIGNED_SHORT, f * faceIdxCount * 2)
        }
        EGL14.eglSwapBuffers(eglDisplay, eglSurface)
    }

    private fun teardownGl() {
        animating = false
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(eglDisplay, eglSurface)
            if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext)
            EGL14.eglTerminate(eglDisplay)
        }
        eglDisplay = EGL14.EGL_NO_DISPLAY; eglSurface = EGL14.EGL_NO_SURFACE; eglContext = EGL14.EGL_NO_CONTEXT
        surface?.release(); entry?.release()
        mainHandler.post { thread.quitSafely() }
    }

    // -------------------------------------------------- Quaternion ([w,x,y,z])
    companion object {
        val FACE_NORMALS = mapOf(
            1 to floatArrayOf(0f, 0f, 1f), 6 to floatArrayOf(0f, 0f, -1f),
            2 to floatArrayOf(1f, 0f, 0f), 5 to floatArrayOf(-1f, 0f, 0f),
            3 to floatArrayOf(0f, -1f, 0f), 4 to floatArrayOf(0f, 1f, 0f),
        )

        fun qMul(a: FloatArray, b: FloatArray) = floatArrayOf(
            a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
            a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
            a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
            a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0],
        )

        fun qAxis(x: Float, y: Float, z: Float, ang: Float): FloatArray {
            val s = sin(ang / 2)
            return floatArrayOf(cos(ang / 2), x * s, y * s, z * s)
        }

        fun qNorm(q: FloatArray): FloatArray {
            val l = sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]).let { if (it < 1e-9f) 1f else it }
            return floatArrayOf(q[0] / l, q[1] / l, q[2] / l, q[3] / l)
        }

        fun qRotate(q: FloatArray, v: FloatArray): FloatArray {
            val w = q[0]; val x = q[1]; val y = q[2]; val z = q[3]
            val tx = 2 * (y * v[2] - z * v[1])
            val ty = 2 * (z * v[0] - x * v[2])
            val tz = 2 * (x * v[1] - y * v[0])
            return floatArrayOf(
                v[0] + w * tx + (y * tz - z * ty),
                v[1] + w * ty + (z * tx - x * tz),
                v[2] + w * tz + (x * ty - y * tx),
            )
        }

        fun qSlerp(a: FloatArray, b: FloatArray, t: Float): FloatArray {
            var dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
            var bb = b
            if (dot < 0) { bb = floatArrayOf(-b[0], -b[1], -b[2], -b[3]); dot = -dot }
            if (dot > 0.9995f) return qNorm(floatArrayOf(
                a[0] + (bb[0] - a[0]) * t, a[1] + (bb[1] - a[1]) * t,
                a[2] + (bb[2] - a[2]) * t, a[3] + (bb[3] - a[3]) * t,
            ))
            val th = acos(min(1f, dot)); val s = sin(th)
            val f1 = sin((1 - t) * th) / s; val f2 = sin(t * th) / s
            return floatArrayOf(
                a[0] * f1 + bb[0] * f2, a[1] * f1 + bb[1] * f2,
                a[2] * f1 + bb[2] * f2, a[3] * f1 + bb[3] * f2,
            )
        }

        /** Rotationsmatrix (Spalten-major 4x4) aus Quaternion (x,y,z,w). */
        fun quatXyzwToMatrix(x: Float, y: Float, z: Float, w: Float, m: FloatArray) {
            val xx = x * x; val yy = y * y; val zz = z * z
            val xy = x * y; val xz = x * z; val yz = y * z
            val wx = w * x; val wy = w * y; val wz = w * z
            m[0] = 1 - 2 * (yy + zz); m[1] = 2 * (xy + wz); m[2] = 2 * (xz - wy); m[3] = 0f
            m[4] = 2 * (xy - wz); m[5] = 1 - 2 * (xx + zz); m[6] = 2 * (yz + wx); m[7] = 0f
            m[8] = 2 * (xz + wy); m[9] = 2 * (yz - wx); m[10] = 1 - 2 * (xx + yy); m[11] = 0f
            m[12] = 0f; m[13] = 0f; m[14] = 0f; m[15] = 1f
        }
    }
}
