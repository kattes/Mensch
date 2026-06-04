program AngerManagement;

uses
  Forms,
  Main in 'Main.pas' {MainForm},
  Spielklassen in 'Spielklassen.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
