unit Main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, Spielklassen, StdCtrls;


type
  TZielfeldInfo = record
    FarbIndex: Integer; // Index der Spielerfarbe: 0 für Rot, 1 für Grün, usw.
    FeldIndex: Integer; // Index des Zielfeldes innerhalb der Farbe: 0 bis 3
  end;
  TMainForm = class(TForm)
    PaintBoxSpielbrett: TPaintBox;
    Label1: TLabel;
    Label2: TLabel;
    Timer1: TTimer;
    procedure FormResize(Sender: TObject);
    procedure FormDblClick(Sender: TObject);
    procedure PaintBoxSpielbrettPaint(Sender: TObject);
    procedure ZeichneFeld(FeldNummer: Integer; Fuellfarbe, Linienfarbe: TColor);
    procedure ZeichneHomebase(PlayerColor: TPlayerColor; AnzahlHome: Integer);
    procedure ZeichneVerbundeneFelder;
    procedure ZeichneZielfelder(PlayerColor: TPlayerColor; ZielfeldBesetzt: TZielFeld);
    function CheckHomeBaseEvent(X, Y: Integer): integer;
    function CheckSpielfeldEvent(x,y: integer): integer;
    function CheckZielfeldEvent(X, Y: Integer): TZielfeldInfo;

    procedure PaintBoxSpielbrettMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxSpielbrettMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure FormCreate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    { Private-Deklarationen }
    Spiel : TSpiel;
    BlinkState : boolean;
  public
    { Public-Deklarationen }
  end;

type
  TFeldPosition = record
    X: Integer;
    Y: Integer;
  end;

const
  FeldPositionen: array[0..39] of TFeldPosition = (
    (X: 1; Y: 5), (X: 2; Y: 5), (X: 3; Y: 5), (X: 4; Y: 5), (X: 5; Y: 5), // 0-4
    (X: 5; Y: 4), (X: 5; Y: 3), (X: 5; Y: 2), (X: 5; Y: 1), (X: 6; Y: 1), // 5-9
    (X: 7; Y: 1), (X: 7; Y: 2), (X: 7; Y: 3), (X: 7; Y: 4), (X: 7; Y: 5), // 10-14
    (X: 8; Y: 5), (X: 9; Y: 5), (X: 10; Y: 5), (X: 11; Y: 5), (X: 11; Y: 6), // 15-19
    (X: 11; Y: 7), (X: 10; Y: 7), (X: 9; Y: 7), (X: 8; Y: 7), (X: 7; Y: 7), // 20-24
    (X: 7; Y: 8), (X: 7; Y: 9), (X: 7; Y: 10), (X: 7; Y: 11), (X: 6; Y: 11), // 25-29
    (X: 5; Y: 11), (X: 5; Y: 10), (X: 5; Y: 9), (X: 5; Y: 8), (X: 5; Y: 7), // 30-34
    (X: 4; Y: 7), (X: 3; Y: 7), (X: 2; Y: 7), (X: 1; Y: 7), (X: 1; Y: 6)  // 35-39
  );

  ZielfeldPositionen: array[0..3, 0..3] of TFeldPosition = (
    ((X: 2; Y: 6), (X: 3; Y: 6), (X: 4; Y: 6), (X: 5; Y: 6)), // Rot
    ((X: 6; Y: 2), (X: 6; Y: 3), (X: 6; Y: 4), (X: 6; Y: 5)), // Grün
    ((X: 10; Y: 6), (X: 9; Y: 6), (X: 8; Y: 6), (X: 7; Y: 6)), // Gelb
    ((X: 6; Y: 10), (X: 6; Y: 9), (X: 6; Y: 8), (X: 6; Y: 7))  // Blau
  );

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

uses
  Math;

function GetColor(fIndex: TPlayerColor): TColor;
begin
  case fIndex of
    pcRed: Result := clRed;
    pcGreen: Result := clGreen;
    pcYellow: Result := rgb(220,220,0);
    pcBlue: Result := clBlue;
  else
    Result := clBlack; // Standardfall oder Fehlerfall
  end;
end;

procedure TMainForm.ZeichneVerbundeneFelder;
var
  i, Offset, FeldRadius, MittelpunktX, MittelpunktY: Integer;
  ErsterMittelpunktX, ErsterMittelpunktY: Integer; // Zum Speichern des ersten Punkts
  VorherigerMittelpunktX, VorherigerMittelpunktY: Integer;
begin
  Offset := PaintBoxSpielbrett.Width div 12; // Annahme: 12 Felder breit für Randabstände
  VorherigerMittelpunktX := -1; // Initialwert, um den ersten Durchgang zu kennzeichnen
  VorherigerMittelpunktY := -1; // Initialwert, um den ersten Durchgang zu kennzeichnen

  with PaintBoxSpielbrett.Canvas do
  begin
    Pen.Width := 5; // Setzt die Linienbreite
    Pen.Color := clBlack; // Farbe der Verbindungslinie

    for i := 0 to 39 do
    begin
      // Berechnet die Position jedes Kreises
      MittelpunktX := FeldPositionen[i].X * Offset; // Korrektur um Mittelpunkt zu berechnen
      MittelpunktY := FeldPositionen[i].Y * Offset; // Korrektur um Mittelpunkt zu berechnen

      // Speichert den ersten Mittelpunkt
      if i = 0 then
      begin
        ErsterMittelpunktX := MittelpunktX;
        ErsterMittelpunktY := MittelpunktY;
      end;

      // Verbindungslinie zum nächsten Kreis zeichnen
      if (VorherigerMittelpunktX >= 0) and (VorherigerMittelpunktY >= 0) then
      begin
        MoveTo(VorherigerMittelpunktX, VorherigerMittelpunktY);
        LineTo(MittelpunktX, MittelpunktY);
      end;

      // Aktuellen Mittelpunkt für die nächste Linie speichern
      VorherigerMittelpunktX := MittelpunktX;
      VorherigerMittelpunktY := MittelpunktY;
    end;

    // Zeichnet die Linie vom letzten zum ersten Punkt, um die Schleife zu schließen
    MoveTo(VorherigerMittelpunktX, VorherigerMittelpunktY);
    LineTo(ErsterMittelpunktX, ErsterMittelpunktY);
  end;
end;


procedure TMainForm.ZeichneFeld(FeldNummer: Integer; Fuellfarbe, Linienfarbe: TColor);
var
  FeldRadius, FeldX, FeldY, Offset: Integer;
begin
  Offset := PaintBoxSpielbrett.Width div 12; // Annahme: 12 Felder breit für Randabstände
  FeldRadius := Offset div 2 -5; // Radius der Kreise

  // Überprüfen, ob die Feldnummer gültig ist
  if (FeldNummer < 0) or (FeldNummer > 39) then Exit;

  with FeldPositionen[FeldNummer], PaintBoxSpielbrett.Canvas do
  begin
    FeldX := X * Offset;
    FeldY := Y * Offset;

    Brush.Color := Fuellfarbe;
    Pen.Color := Linienfarbe;
    if Linienfarbe=clBlack then
      Pen.Width := 3 // Setzt die Linienbreite
    else
      Pen.Width := 5; // Setzt die Linienbreite

    // Zeichnet den Kreis an der berechneten Position
    Ellipse(FeldX - FeldRadius, FeldY - FeldRadius, FeldX + FeldRadius, FeldY + FeldRadius);
  end;
end;

procedure TMainForm.ZeichneHomebase(PlayerColor: TPlayerColor; AnzahlHome: Integer);
const
  cPW = 5; // Stiftbreite
var
  FeldGroesse, StartX, StartY, FeldX, FeldY, Radius, i: Integer;
  Farbe, Fuellfarbe: TColor;
begin
  FeldGroesse := Min(PaintBoxSpielbrett.Width, PaintBoxSpielbrett.Height) div 11; // Größe jedes Feldes
  Radius := (FeldGroesse - cPW) div 2; // Radius der Kreise anpassen

  // Bestimme die Startposition für jede Farbe
  case PlayerColor of
    pcRed:    begin StartX := cPW; StartY := cPW; Farbe := clRed; end;
    pcGreen:  begin StartX := PaintBoxSpielbrett.Width - (2 * FeldGroesse) + cPW; StartY := cPW; Farbe := clGreen; end;
    pcYellow: begin StartX := PaintBoxSpielbrett.Width - (2 * FeldGroesse) + cPW; StartY := PaintBoxSpielbrett.Height - (2 * FeldGroesse) + cPW; Farbe := GetColor(pcYellow); end;
    pcBlue:   begin StartX := cPW; StartY := PaintBoxSpielbrett.Height - (2 * FeldGroesse) + cPW; Farbe := clBlue; end;
  else Exit;
  end;

  PaintBoxSpielbrett.Canvas.Pen.Width := cPW;
  PaintBoxSpielbrett.Canvas.Pen.Color := Farbe; // Setzt die Umrandung der Kreise

  // Zeichnet vier Felder pro Homebase
  for i := 0 to 3 do
  begin
    FeldX := StartX + (i mod 2) * FeldGroesse + Radius; // Berücksichtigt die Stiftbreite und Radius
    FeldY := StartY + (i div 2) * FeldGroesse + Radius; // Berücksichtigt die Stiftbreite und Radius

    if i < AnzahlHome then
      Fuellfarbe := Farbe // Besetzte Felder in Spielerfarbe
    else
      Fuellfarbe := clWhite; // Leere Felder in Silber

    PaintBoxSpielbrett.Canvas.Brush.Color := Fuellfarbe;
    // Korrigiert die Position und Größe unter Berücksichtigung der Stiftbreite
    PaintBoxSpielbrett.Canvas.Ellipse(FeldX - Radius, FeldY - Radius, FeldX + Radius, FeldY + Radius);
  end;
end;

procedure TMainForm.ZeichneZielfelder(PlayerColor: TPlayerColor; ZielfeldBesetzt: TZielFeld);
var
  i, Offset, FeldRadius, FeldX, FeldY: Integer;
  Farbe: TColor;
begin
  Offset := PaintBoxSpielbrett.Width div 12; // Annahme: 12 Felder breit für Randabstände
  FeldRadius := Offset div 2 - 10; // Radius der Kreise
  Farbe := GetColor(PlayerColor);

  for i := 0 to High(ZielfeldBesetzt) do
  begin
    with ZielfeldPositionen[ord(PlayerColor), i] do
    begin
      FeldX := X * Offset - FeldRadius;
      FeldY := Y * Offset - FeldRadius;

      PaintBoxSpielbrett.Canvas.Brush.Color := IfThen(ZielfeldBesetzt[i], Farbe, clWhite); // clGray als Beispiel für besetzte Felder
      PaintBoxSpielbrett.Canvas.Pen.Color := Farbe;
      PaintBoxSpielbrett.Canvas.Ellipse(FeldX, FeldY, FeldX + 2 * FeldRadius, FeldY + 2 * FeldRadius);
    end;
  end;
end;


procedure TMainForm.FormCreate(Sender: TObject);
begin
  Mainform.DoubleBuffered := true;
  Spiel:= TSpiel.Create;
  Spiel.GetSpieler(pcRed).SpielerTyp := stMensch;
  Spiel.GetSpieler(pcRed).GetSpielfigur(1).Position :=39;
  Spiel.GetSpieler(pcRed).GetSpielfigur(2).Position :=5;
  Spiel.GetSpieler(pcRed).GetSpielfigur(3).Position :=17;
  Spiel.GetSpieler(pcGreen).SpielerTyp := stMensch;
  Spiel.GetSpieler(pcGreen).GetSpielfigur(1).Position :=38;
  Spiel.GetSpieler(pcGreen).GetSpielfigur(2).PositionImZielfeld := 1;
  Spiel.Highlight := true;
  Spiel.AktiveFarbe := pcGreen;
end;

procedure TMainForm.FormDblClick(Sender: TObject);
begin
  close;
end;

procedure TMainForm.FormResize(Sender: TObject);
var
  b,h,w : integer;
begin
  b := MainForm.Width;
  h := MainForm.Height;
  w := min(b,h);
  PaintBoxSpielbrett.Width := w;
  PaintBoxSpielbrett.Height := w;
  if b>h then
  begin
    PaintBoxSpielbrett.Left := (b-w) div 2;
    PaintBoxSpielbrett.Top := 0;
  end
  else
  begin
    PaintBoxSpielbrett.Left := 0;
    PaintBoxSpielbrett.Top := (h-w) div 2;
  end;
end;

function TMainForm.CheckHomeBaseEvent(X, Y: Integer): integer;
const
  cPW = 0; // Stiftbreite
var
  FeldGroesse, StartX, StartY, FeldX, FeldY, Radius, i, QuadratSeite: Integer;
  Farbe, Fuellfarbe: TColor;
begin
  FeldGroesse := Min(PaintBoxSpielbrett.Width, PaintBoxSpielbrett.Height) div 11; // Größe jedes Feldes
  Radius := (FeldGroesse - cPW) div 2; // Radius der Kreise anpassen
  QuadratSeite := 4 * Radius; // Seite des Quadrats, das die Homebase umschreibt

  result := -1;
  // Rot in der oberen linken Ecke
  if (X <= QuadratSeite) and (Y <= QuadratSeite) then
  begin
    result := 0; // Rot
  end
  // Grün in der oberen rechten Ecke
  else if (X >= PaintBoxSpielbrett.Width - QuadratSeite) and (Y <= QuadratSeite) then
  begin
    result := 1; // Grün
  end
  // Gelb in der unteren rechten Ecke
  else if (X >= PaintBoxSpielbrett.Width - QuadratSeite) and (Y >= PaintBoxSpielbrett.Height - QuadratSeite) then
  begin
    result := 2; // Gelb
  end
  // Blau in der unteren linken Ecke
  else if (X <= QuadratSeite) and (Y >= PaintBoxSpielbrett.Height - QuadratSeite) then
  begin
    result := 3; // Blau
  end
  else
  begin
    Exit; // Keine Homebase wurde angeklickt
  end;
end;

function  TMainForm.CheckSpielfeldEvent(x,y: integer): integer;
var
  i, Offset, FeldRadius, FeldLinks, FeldOben: Integer;
  KlickInnerhalbFeld: Boolean;
begin
  Offset := PaintBoxSpielbrett.Width div 12; // Annahme: 12 Felder breit für Randabstände
  FeldRadius := Offset div 2; // Radius der Kreise
  result := -1;
  for i := 0 to 39 do
  begin
    FeldLinks := FeldPositionen[i].X * Offset - FeldRadius;
    FeldOben := FeldPositionen[i].Y * Offset - FeldRadius;

    // Überprüft, ob der Klick innerhalb des Rechtecks liegt, das die Ellipse umschließt
    KlickInnerhalbFeld := (X >= FeldLinks) and (X <= FeldLinks + 2 * FeldRadius) and
                          (Y >= FeldOben) and (Y <= FeldOben + 2 * FeldRadius);

    if KlickInnerhalbFeld then
    begin
      result := i;
      Break; // Beendet die Schleife, da das Feld gefunden wurde
    end;
  end;
end;

function TMainForm.CheckZielfeldEvent(X, Y: Integer): TZielfeldInfo;
var
  i, j, Offset, FeldRadius, FeldLinks, FeldOben: Integer;
begin
  Offset := PaintBoxSpielbrett.Width div 12; // Annahme: 12 Felder breit für Randabstände
  FeldRadius := Offset div 2; // Radius der Kreise
  Result.FarbIndex := -1; // Initialwert, zeigt an, dass keine Zielfeld angeklickt wurde
  Result.FeldIndex := -1; // Initialwert

  for j := 0 to High(ZielfeldPositionen) do // Für jede Farbe
  begin
    for i := 0 to High(ZielfeldPositionen[j]) do // Für jedes Zielfeld
    begin
      FeldLinks := ZielfeldPositionen[j, i].X * Offset - FeldRadius;
      FeldOben := ZielfeldPositionen[j, i].Y * Offset - FeldRadius;

      // Überprüft, ob der Klick innerhalb des Rechtecks liegt, das die Ellipse umschließt
      if (X >= FeldLinks) and (X <= FeldLinks + 2 * FeldRadius) and
         (Y >= FeldOben) and (Y <= FeldOben + 2 * FeldRadius) then
      begin
        Result.FarbIndex := j; // Setzt den Farbindex
        Result.FeldIndex := i; // Setzt den Feldindex
        Exit; // Beendet die Funktion, da das Zielfeld gefunden wurde
      end;
    end;
  end;
end;

procedure TMainForm.PaintBoxSpielbrettMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  id: Integer;
  ZielfeldInfo: TZielfeldInfo;
begin
  ZielfeldInfo := CheckZielfeldEvent(X, Y);
  if (ZielfeldInfo.FarbIndex <> -1) and (ZielfeldInfo.FeldIndex <> -1) then
  begin
    // Reagiere auf den Klick im Zielfeld
    Label2.Caption := Format('Zielfeld: Farbe %d, Pos %d',
              [ZielfeldInfo.FarbIndex, ZielfeldInfo.FeldIndex]);
  end;
  id := CheckHomeBaseEvent(x,y);
  if id>=0 then
  begin
    Label2.Caption := 'Homebase:'+IntToStr(id);
    exit;
  end;

  id := CheckSpielfeldEvent(x,y);
  if id>=0 then
  begin
    Label2.Caption := 'Angeklicktes Feld: ' + IntToStr(id);
    exit;
  end;
end;

procedure TMainForm.PaintBoxSpielbrettMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  Label1.Caption := InttoStr(x)+':'+IntToStr(y);
end;

procedure TMainForm.PaintBoxSpielbrettPaint(Sender: TObject);
var
  i, j, k: Integer;
  FFill, FPen: TColor;
  iC, Farbe : TPlayerColor;
  Spieler : TSpieler;
  aF : TZielfeld;
begin
  for i := 0 to 3 do
    af[i] := false;

  // Hintergrund zeichnen
  with PaintBoxSpielbrett.Canvas do
  begin
    Brush.Color := rgb(255, 255, 200);  // Helles Gelb
    FillRect(Rect(0, 0, PaintBoxSpielbrett.Width, PaintBoxSpielbrett.Height));
  end;

  // Verbindende Linien zeichnen
  ZeichneVerbundeneFelder;

  // Standardfelder zeichnen
  for i := 0 to 39 do
  begin
    FFill := clWhite;
    FPen := clBlack; // Standardfarbe für die Linien
    case i of
      0: FPen := clRed;    // Startfeld für Rot
      10: FPen := clGreen;  // Startfeld für Grün
      20: FPen := GetColor(pcYellow); // Startfeld für Gelb
      30: FPen := clBlue;   // Startfeld für Blau
    end;

    ZeichneFeld(i, FFill, FPen);
  end;

  // Homebases für jeden Spieler zeichnen
  for iC := pcRed to pcBlue do
  begin
    Spieler := Spiel.GetSpieler(iC);
    if Spieler.SpielerTyp <> stNichtAktiv then
    begin
      // Die Anzahl der Figuren in der Homebase könnte dynamisch berechnet werden,
      // basierend auf der Position jeder Figur
      ZeichneHomebase(ic, Spieler.GetAnzahlHomebase); // Ersetze 4 durch die tatsächliche Anzahl
    end;
  end;

  // Spielfiguren auf dem Brett zeichnen
  for iC := pcRed to pcBlue do
  begin
    Spieler := Spiel.GetSpieler(ic);
    if (Spieler.SpielerTyp = stNichtAktiv) OR
      ((Spiel.Highlight) AND (Spiel.AktiveFarbe=iC) AND BlinkState) then
    begin
      // Spieler ist nicht aktiv, also zeichne leere Homebase und das leere Zielfeld
      ZeichneHomebase(iC,0);
      for k := 0 to 3 do
        af[k] := false;
      ZeichneZielfelder(iC, aF);
    end
    else
    begin
      for j := 1 to 4 do
      begin
        with Spieler.GetSpielfigur(j) do
        begin
          // Bestimme die Farbe der Spielfigur
          FPen := GetColor(Color);

          // Zeichne die Spielfigur basierend auf ihrer Position
          if Position >= 0 then
          begin
            ZeichneFeld(Position, FPen, FPen);
          end;

          // Hier könnte eine zusätzliche Logik eingefügt werden,
          // um Spielfiguren im Zielfeld zu zeichnen
        end;
      end;
      ZeichneZielfelder(iC, Spieler.GetZielfeldArray);
    end;
  end;
end;

procedure TMainForm.Timer1Timer(Sender: TObject);
begin
  if Spiel.Highlight then
  begin
    BlinkState := not BlinkState; // Wechselt den Zustand
    PaintBoxSpielbrett.Invalidate; // Erzwingt Neuzeichnen
  end
  else
    Timer1.Enabled := False; // Deaktiviert den Timer, wenn Highlighting nicht benötigt wird
end;


end.
