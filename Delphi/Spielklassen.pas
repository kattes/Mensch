unit Spielklassen;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls;

type
  TPlayerColor = (pcRed, pcGreen, pcYellow, pcBlue);
  TSpielerTyp = (stMensch, stKI, stNichtAktiv);
  TZielfeld = array[0..3] of Boolean;

  TSpielfigur = class
  private
    FPlayerColor: TPlayerColor;
    FPositionImZielfeld: Integer; // 0 für nicht im Ziel, 1..4 für Position im Zielfeld
    FPosition: Integer; // -1 für Homebase, 0..39 für Spielfeldpositionen
  public
    constructor Create(Color: TPlayerColor);
    procedure Bewege(vorwaerts: Integer);
    procedure BewegeImZielfeld(vorwaerts: Integer);
    property Color: TPlayerColor read FPlayerColor write FPlayerColor;
    property Position: Integer read FPosition write FPosition;
    property PositionImZielfeld: Integer read FPositionImZielfeld write FPositionImZielfeld;
  end;

  TSpieler = class
  private
    FSpielerTyp: TSpielerTyp;
    FSpielerfarbe: TPlayerColor;
    FSpielfiguren: array[1..4] of TSpielfigur;
  public
    function GetSpielfigur(Index: integer): TSpielfigur;
    constructor Create(SpielerTyp: TSpielerTyp; Spielerfarbe: TPlayerColor);
    function GetZielfeldArray : TZielfeld;
    function GetAnzahlHomebase: integer;
    procedure ZugAusfuehren(iWuerfel: Integer);
    property SpielerTyp: TSpielerTyp read FSpielerTyp write FSpielerTyp;
    property Spielerfarbe: TPlayerColor read FSpielerfarbe write FSpielerfarbe;
  end;

  TSpiel = class
  private
    FSpieler: array[1..4] of TSpieler;
    FAktiveFarbe : TPlayerColor;
    FHighLight : boolean;
    procedure InitialisiereSpieler;
  public
    constructor Create;
    function GetSpieler(TPlayerColor: TPlayerColor): TSpieler;
    procedure StarteSpiel;
    procedure SetSpielerStatus(Farbe: TPlayerColor; SpielerTyp: TSpielerTyp);
    function GetSpielerKonfiguration: String;
    procedure SetHighLight(hl: boolean);
    property Highlight: boolean read FHighLight write SetHighLight;
    property AktiveFarbe: TPlayerColor read FAktiveFarbe write FAktiveFarbe;
  end;

implementation

{ TSpielfigur }

constructor TSpielfigur.Create(Color: TPlayerColor);
begin
  inherited Create;
  FPlayerColor := Color;
  FPosition := -1; // Startet in der Homebase
  FPositionImZielfeld := 0; // Noch nicht im Ziel
end;

procedure TSpielfigur.Bewege(vorwaerts: Integer);
begin
  if FPosition = -1 then Exit; // Kann sich nicht bewegen, wenn in der Homebase
  FPosition := (FPosition + vorwaerts) mod 40; // Bewegung auf dem Spielfeld
end;

procedure TSpielfigur.BewegeImZielfeld(vorwaerts: Integer);
begin
  if (FPositionImZielfeld + vorwaerts > 4) then Exit; // Kann nicht über das Ziel hinaus
  FPositionImZielfeld := FPositionImZielfeld + vorwaerts;
end;

{ TSpieler }

constructor TSpieler.Create(SpielerTyp: TSpielerTyp; Spielerfarbe: TPlayerColor);
var
  i: Integer;
begin
  inherited Create;
  FSpielerTyp := SpielerTyp;
  FSpielerfarbe := Spielerfarbe;
  for i := 1 to 4 do
    FSpielfiguren[i] := TSpielfigur.Create(Spielerfarbe); // Initialisiert die Spielfiguren
end;

function TSpieler.GetAnzahlHomebase: integer;
var
  i: Integer;
begin
  Result := 4;
  for i := 1 to 4 do
  begin
    // Eine Figur zählt zur Homebase, wenn sie weder auf dem Spielfeld positioniert ist
    // noch sich im Zielfeld befindet.
    if (FSpielfiguren[i].FPosition >-1) OR (FSpielfiguren[i].FPositionImZielfeld >0) then
    begin
      dec(Result); // Erhöhe die Anzahl, wenn eine Figur in der Homebase ist und nicht im Ziel
    end;
  end;
end;

function TSpieler.GetSpielfigur(Index: integer): TSpielfigur;
begin
  result := FSpielfiguren[index];
end;

function TSpieler.GetZielfeldArray: TZielfeld;
var
  i, j: Integer;
begin
  // Initialisiere alle Werte im Ergebnisarray mit False
  for i := 0 to 3 do
  begin
    Result[i] := False;
  end;

  // Durchlaufe jedes potenzielle Zielfeld
  for i := 0 to 3 do
  begin
    // Überprüfe jede Spielfigur, um zu sehen, ob sie sich auf dem Zielfeld i befindet
    for j := 1 to 4 do
    begin
      if FSpielfiguren[j].FPositionImZielfeld = i+1 then
      begin
        // Markiere das Zielfeld i als besetzt
        Result[i] := True;
        Break; // Breche die innere Schleife ab, da das Zielfeld bereits besetzt ist
      end;
    end;
  end;
end;

procedure TSpieler.ZugAusfuehren(iWuerfel: Integer);
begin
  // Hier sollte die Logik für den Zug des Spielers implementiert werden
  // Diese Methode ist nur ein Platzhalter und muss je nach Spiellogik angepasst werden
end;

{ TSpiel }

constructor TSpiel.Create;
begin
  inherited Create;
  InitialisiereSpieler; // Initialisiert alle Spieler als nicht aktiv
end;

procedure TSpiel.InitialisiereSpieler;
var
  i: Integer;
begin
  for i := 1 to 4 do
    FSpieler[i] := TSpieler.Create(stNichtAktiv, TPlayerColor(i - 1)); // Setzt alle Spieler standardmäßig auf nicht aktiv
end;

procedure TSpiel.StarteSpiel;
begin
  // Starte das Spiel. Die Implementierung hängt von deiner spezifischen Spiellogik ab
end;

procedure TSpiel.SetHighLight(hl: boolean);
begin
  FHighLight := hl;
end;

procedure TSpiel.SetSpielerStatus(Farbe: TPlayerColor; SpielerTyp: TSpielerTyp);
begin
  FSpieler[Ord(Farbe) + 1].SpielerTyp := SpielerTyp; // Aktualisiert den Typ des Spielers basierend auf der Farbe
end;

function TSpiel.GetSpieler(TPlayerColor: TPlayerColor): TSpieler;
begin
  result := FSpieler[ord(TPlayerColor)+1];
end;

function TSpiel.GetSpielerKonfiguration: String;
var
  i: Integer;
  Konfiguration: String;
begin
  Konfiguration := '';
  for i := 1 to 4 do
  begin
    Konfiguration := Konfiguration + 'Spieler ' + IntToStr(i) + ': ' +
                     IntToStr(Ord(FSpieler[i].SpielerTyp)) + sLineBreak;
  end;
  Result := Konfiguration;
end;

end.

