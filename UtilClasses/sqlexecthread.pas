{
  *******************************************************************
  AUTHOR : Flakron Shkodra 2011
  *******************************************************************
}

unit SqlExecThread;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DB, sqldb, mssqlconn, SQLDBLaz, AsDbType, strutils,ZDataset,syncobjs;

type

  { TSqlExecThread }

  TOnSqlExecThreadFinish = procedure(Sender: TObject; IsTableData:boolean) of object;

  TSqlExecThread = class(TThread)
  private
    FLock:TCriticalSection;
    FExecutionTime: TTime;
    FExecuteAsThread: boolean;
    FLastError: string;
    FMessage: string;
    FOnFinish: TOnSqlExecThreadFinish;
    FQuery: TSQLQuery;
    FZQuery:TZQuery;
    FRecordCount: word;
    FSchema: string;
    FActive: boolean;
    FCommand: string;
    FTablenameAssigned:Boolean;
    FIsSelect:Boolean;
    function GetOriginalQuery: string;
    function GetResultSet: TDBDataset;
    procedure SetDurationTime(AValue: TTime);
    procedure SetExecuteAsThread(AValue: boolean);
    procedure SetLastError(AValue: string);
    procedure SetMessage(AValue: string);
    procedure SetOnFinish(AValue: TOnSqlExecThreadFinish);
    procedure SetRecordCount(AValue: word);
  protected
    procedure Execute; override;
    procedure SqlExecute;
  public


    constructor Create(Schema: string; sqlQuery: TSQLQuery;
     OnFinish: TOnSqlExecThreadFinish); overload;
    constructor Create(Schema:string; sqlQuery:TZQuery; OnFinish:TOnSqlExecThreadFinish);overload;
    property Active: boolean read FActive;
    property LastError: string read FLastError write SetLastError;
    procedure ExecuteSQL(sqlCommand: string; TableData:Boolean);
    property ExecuteAsThread: boolean read FExecuteAsThread write SetExecuteAsThread;
    property ExecutionTime: TTime read FExecutionTime;
    property RecordCount: word read FRecordCount;
    property OnFinish: TOnSqlExecThreadFinish read FOnFinish write SetOnFinish;
    property Message: string read FMessage write SetMessage;
    property IsSelect:Boolean read FIsSelect;
    destructor Destroy; override;

  end;

implementation

uses AsSqlParser;

{ TSqlExecThread }

function IsUTF8String(S: string): boolean;
var
  WS: WideString;
begin
  WS := UTF8Decode(S);
  Result := (WS <> S) and (WS <> '');
end;


procedure TSqlExecThread.SetMessage(AValue: string);
begin
  if FMessage = AValue then
    Exit;
  FMessage := AValue;
end;

procedure TSqlExecThread.SetLastError(AValue: string);
begin
  if FLastError = AValue then
    Exit;
  FLastError := AValue;
end;

function TSqlExecThread.GetResultSet: TDBDataset;
begin
  Result := FQuery;
end;

function TSqlExecThread.GetOriginalQuery: string;
begin
  Result := FCommand;
end;


procedure TSqlExecThread.SetDurationTime(AValue: TTime);
begin
  if FExecutionTime = AValue then
    Exit;
  FExecutionTime := AValue;
end;

procedure TSqlExecThread.SetExecuteAsThread(AValue: boolean);
begin
  if FExecuteAsThread = AValue then
    Exit;
  FExecuteAsThread := AValue;
end;


procedure TSqlExecThread.SetOnFinish(AValue: TOnSqlExecThreadFinish);
begin
  if FOnFinish = AValue then
    Exit;
  FOnFinish := AValue;
end;


procedure TSqlExecThread.SetRecordCount(AValue: word);
begin
  if FRecordCount = AValue then
    Exit;
  FRecordCount := AValue;
end;

procedure TSqlExecThread.Execute;
begin
  FLastError := EmptyStr;
  FActive := True;
  try
    try
      SqlExecute;
    except
      on e: Exception do
      begin
        FLastError := e.Message;
      end;
    end;

    if Assigned(FOnFinish) then
      FOnFinish(Self, FTablenameAssigned);
  finally
    FActive := False;
  end;
end;

procedure TSqlExecThread.SqlExecute;
var
  I: integer;
  tmpCommand: string;
  t1: TTime;
  Handled: boolean;
  c:Boolean;
  affected:Integer;
begin
  //FLock.Acquire; //fails with zeos components
  try
   FIsSelect:=True;
   try
     FLastError := '';
     c := (FQuery<>nil) or (FZQuery<>nil);

     if not c then
     begin
       FLastError:='Internal FQuery not assigned';
       FOnFinish(Self,FTablenameAssigned);
       Exit;
     end;


     //IsSelect :=[expression] {doesn't seem to compile}
     if ( (AnsiContainsText(Lowercase(FCommand), 'insert into ')) or
       (AnsiContainsText(Lowercase(FCommand), 'update ')) or
       (AnsiContainsText(Lowercase(FCommand), 'delete from ')) or
       (AnsiContainsText(LowerCase(FCommand), 'alter ')) or
       (AnsiContainsText(LowerCase(FCommand), 'drop ')) or
       (AnsiContainsText(LowerCase(FCommand), 'create '))
       ) then FIsSelect:=False;

     Sleep(300);

     t1 := Time;

     if not FIsSelect then
     begin
       if Assigned(FQuery) then
       begin
        FQuery.Close;
        FQuery.SQL.Text := FCommand;
        FQuery.ExecSQL;
        affected:=FQuery.RowsAffected;
       end else
       if Assigned(FZQuery) then
       begin
        FZQuery.Close;
        FZQuery.SQL.Text := FCommand;
        FZQuery.ExecSQL;
        affected:=FZQuery.RowsAffected;
       end;
       FExecutionTime := Time - t1;
       FMessage := 'Command successfully executed. Rows affected (' +IntToStr(affected) + ')';
     end
     else
     begin
       if Assigned(FQuery) then
       begin
         FQuery.Close;
         FQuery.SQL.Text:=FCommand;
         FQuery.PacketRecords:=-1;
         FQuery.Open;
         FRecordCount := FQuery.RecordCount;
       end
       else if Assigned(FZQuery) then
       begin
         FZQuery.Close;
         FZQuery.SQL.Text:=FCommand;
         FZQuery.Open;
         FRecordCount := FZQuery.RecordCount;
       end;
       FExecutionTime:= Time-t1;

       FMessage := 'Execution time [' + TimeToStr(Time-t1) + '] Records [' +
         IntToStr(FRecordCount) + ']';
     end;
   except
     on e: Exception do
     begin
       FLastError := e.Message;
     end;
   end;

  finally
  //  FLock.Release;
  end;

end;

constructor TSqlExecThread.Create(Schema: string; sqlQuery: TSQLQuery;
 OnFinish: TOnSqlExecThreadFinish);
begin
  FLock := TCriticalSection.Create;
  FSchema := Schema;
  FQuery := sqlQuery;
  FExecuteAsThread := True;
  FOnFinish := OnFinish;
  inherited Create(True);
  inherited FreeOnTerminate:=True;
end;

constructor TSqlExecThread.Create(Schema: string; sqlQuery: TZQuery;
 OnFinish: TOnSqlExecThreadFinish);
begin
  FLock.Free;
  FSchema := Schema;
  FZQuery := sqlQuery;
  FExecuteAsThread := True;
  FOnFinish := OnFinish;
  inherited Create(True);
  inherited FreeOnTerminate:=True;
end;


procedure TSqlExecThread.ExecuteSQL(sqlCommand: string; TableData: Boolean);
begin
  FtableNameAssigned:=TableData;
  if Trim(sqlCommand) <> EmptyStr then
    FCommand := sqlCommand
  else
  begin
    raise Exception.Create('No SqlCommand');
  end;

  if FExecuteAsThread then
  begin
    inherited Start;
  end
  else
  begin
    SqlExecute;
  end;

end;

destructor TSqlExecThread.Destroy;
begin
  inherited Destroy;
end;

end.
