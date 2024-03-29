unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, Process, DefaultTranslator, IniPropStorage;

type
  TCharSet = set of char;

  { TMainForm }

  TMainForm = class(TForm)
    Bevel1: TBevel;
    CreateBtn: TButton;
    IniPropStorage1: TIniPropStorage;
    Label1: TLabel;
    ReloadBtn: TButton;
    FlashDriveBox: TComboBox;
    SaveDialog1: TSaveDialog;
    procedure CreateBtnClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ReloadBtnClick(Sender: TObject);

  private

  public

  end;

//Ресурсы перевода
resourcestring
  SWarning1 = 'The user "';
  SWarning2 = '" is not in groups "disk", "vboxusers" and "vboxsf"' +
    #13#10 + #13#10 + 'Run the command in terminal (su/password):' +
    #13#10 + 'usermod -a -G disk,vboxusers,vboxsf $USER' + #13#10 +
    #13#10 + '...and reboot your computer to apply privileges!';

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ TMainForm }

//Определяем вхождение $USER в группы disk и vboxusers
function UserInGroups: boolean;
var
  S: TStringList;
  ExProcess: TProcess;
begin
  S := TStringList.Create;

  ExProcess := TProcess.Create(nil);
  Screen.Cursor := crHourGlass;
  try
    ExProcess.Executable := 'bash';
    ExProcess.Options := ExProcess.Options + [poUsePipes, poWaitOnExit];
    ExProcess.Parameters.Add('-c');

    ExProcess.Parameters.Add('groups | grep "disk" | grep "vboxusers" | grep "vboxsf"');

    ExProcess.Execute;

    S.LoadFromStream(ExProcess.Output);

    if S.Count > 0 then
      Result := True
    else
      Result := False;

  finally
    S.Free;
    ExProcess.Free;
    Screen.Cursor := crDefault;
  end;
end;

//Позиция слова в строке
function WordPosition(const N: integer; const S: string;
  const WordDelims: TCharSet): integer;
var
  Count, I: integer;
begin
  Count := 0;
  I := 1;
  Result := 0;
  while (I <= Length(S)) and (Count <> N) do
  begin
    { skip over delimiters }
    while (I <= Length(S)) and (S[I] in WordDelims) do
      Inc(I);
    { if we're not beyond end of S, we're at the start of a word }
    if I <= Length(S) then
      Inc(Count);
    { if not finished, find the end of the current word }
    if Count <> N then
      while (I <= Length(S)) and not (S[I] in WordDelims) do
        Inc(I)
    else
      Result := I;
  end;
end;

//Выделение слова в строке
function ExtractWord(N: integer; const S: string; const WordDelims: TCharSet): string;
var
  I: integer;
  Len: integer;
begin
  Len := 0;
  I := WordPosition(N, S, WordDelims);
  if I <> 0 then
    { find the end of the current word }
    while (I <= Length(S)) and not (S[I] in WordDelims) do
    begin
      { add the I'th character to result }
      Inc(Len);
      SetLength(Result, Len);
      Result[Len] := S[I];
      Inc(I);
    end;
  SetLength(Result, Len);
end;

//Начитываем список флешек
procedure TMainForm.ReloadBtnClick(Sender: TObject);
var
  ExProcess: TProcess;
begin
  ExProcess := TProcess.Create(nil);

  Screen.Cursor := crHourGlass;
  try
    ExProcess.Executable := 'bash';
    ExProcess.Options := ExProcess.Options + [poWaitOnExit];
    ExProcess.Parameters.Add('-c');

    ExProcess.Parameters.Add(
      '>~/.vboxvdc/devlist; dev=$(lsblk -ldn | cut -f1 -d" ");' +
      'for i in $dev; do if [[ $(cat /sys/block/$i/removable) -eq 1 ]]; then ' +
      'echo "/dev/$(lsblk -ld | grep $i | awk ' + '''' + '{print $1,$4}' +
      '''' + ')" | grep -Ev "\/dev\/sr|0B" >> ~/.vboxvdc/devlist; fi; done');

    ExProcess.Execute;

    FlashDriveBox.Items.LoadFromFile(GetUserDir + '.vboxvdc/devlist');

    if FlashDriveBox.Items.Count <> 0 then
      FlashDriveBox.ItemIndex := 0;

  finally
    ExProcess.Free;
    Screen.Cursor := crDefault;
  end;

  if FlashDriveBox.Items.Count = 0 then
    CreateBtn.Enabled := False
  else
    CreateBtn.Enabled := True;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  //Папка файлов конфигурации
  if not DirectoryExists(GetUserDir + '.vboxvdc') then MkDir(GetUserDir + '.vboxvdc');

  IniPropStorage1.IniFileName := GetUserDir + '.vboxvdc/settings';

  //Начитываем список блочных устройств
  ReloadBtn.Click;

  //Ищем рабочий стол
  if DirectoryExists(GetEnvironmentVariable('HOME') + '/Рабочий стол') then
    SaveDialog1.InitialDir := GetEnvironmentVariable('HOME') +
      '/Рабочий стол'
  else
  if DirectoryExists(GetEnvironmentVariable('HOME') + '/Desktop') then
    SaveDialog1.InitialDir := GetEnvironmentVariable('HOME') + '/Desktop'
  else
    SaveDialog1.InitialDir := '/home';
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  IniPropStorage1.Restore;
  MainForm.Caption := Application.Title;
end;

procedure TMainForm.CreateBtnClick(Sender: TObject);
var
  ExProcess: TProcess;
begin
  //Проверяем вхождение $USER в группы disk и vboxusers
  if not UserInGroups then
  begin
    MessageDlg(SWarning1 + GetEnvironmentVariable('USER') + SWarning2,
      mtWarning, [mbOK], 0);

    Exit;
  end;

  //Даём умолчальное название файла
  SaveDialog1.FileName := 'USB_Device_' + ExtractWord(2, FlashDriveBox.Text,
    [' ']) + '.vmdk';

  if SaveDialog1.Execute then
  begin
    ExProcess := TProcess.Create(nil);
    Screen.Cursor := crHourGlass;
    try
      ExProcess.Executable := 'bash';
      ExProcess.Options := ExProcess.Options + [poUsePipes]; //, poWaitOnExit];
      ExProcess.Parameters.Add('-c');

      ShowMessage(ExtractWord(1, FlashDriveBox.Text, [' ']));

      //VirtrualBox-7.0.3 and higher support
      //https://forums.virtualbox.org/viewtopic.php?f=7&p=526014#p525908
      ExProcess.Parameters.Add(
        'VBoxManage createmedium disk --filename "' + SaveDialog1.FileName +
        '" --format=VMDK --variant RawDisk --property RawDrive=' +
        ExtractWord(1, FlashDriveBox.Text, [' ']));

      ExProcess.Execute;

    finally
      ExProcess.Free;
      Screen.Cursor := crDefault;
    end;
  end;
end;

end.
