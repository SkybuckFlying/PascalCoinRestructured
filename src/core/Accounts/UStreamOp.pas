unit UStreamOp;

interface

uses
  Classes, UAccountKey, URawBytes;

type
  { TStreamOp }
  TStreamOp = Class
  public
    class Function WriteAnsiString(Stream: TStream; const value: AnsiString): Integer; overload;
    class Function ReadAnsiString(Stream: TStream; var value: AnsiString): Integer; overload;
    class Function WriteAccountKey(Stream: TStream; const value: TAccountKey): Integer;
    class Function ReadAccountKey(Stream: TStream; var value : TAccountKey): Integer;
    class Function SaveStreamToRaw(Stream: TStream) : TRawBytes;
    class procedure LoadStreamFromRaw(Stream: TStream; const raw : TRawBytes);
  End;

implementation

uses
  ULog, SysUtils, UECDSA_Public;

{ TStreamOp }

class function TStreamOp.ReadAccountKey(Stream: TStream; var value: TAccountKey): Integer;
begin
  if Stream.Size - Stream.Position < 2 then begin
    value := CT_TECDSA_Public_Nul;
    Result := -1;
    exit;
  end;
  stream.Read(value.EC_OpenSSL_NID,SizeOf(value.EC_OpenSSL_NID));
  if (ReadAnsiString(stream,value.x)<=0) then begin
    value := CT_TECDSA_Public_Nul;
    exit;
  end;
  if (ReadAnsiString(stream,value.y)<=0) then begin
    value := CT_TECDSA_Public_Nul;
    exit;
  end;
  Result := value.EC_OpenSSL_NID;
end;

class function TStreamOp.SaveStreamToRaw(Stream: TStream): TRawBytes;
begin
  SetLength(Result,Stream.Size);
  Stream.Position:=0;
  Stream.ReadBuffer(Result[1],Stream.Size);
end;

class procedure TStreamOp.LoadStreamFromRaw(Stream: TStream; const raw: TRawBytes);
begin
  Stream.WriteBuffer(raw[1],Length(raw));
end;

class function TStreamOp.ReadAnsiString(Stream: TStream; var value: AnsiString): Integer;
Var
  l: Word;
begin
  if Stream.Size - Stream.Position < 2 then begin
    value := '';
    Result := -1;
    exit;
  end;
  Stream.Read(l, 2);
  if Stream.Size - Stream.Position < l then begin
    Stream.Position := Stream.Position - 2; // Go back!
    value := '';
    Result := -1;
    exit;
  end;
  SetLength(value, l);
  Stream.ReadBuffer(value[1], l);
  Result := l+2;
end;

class function TStreamOp.WriteAccountKey(Stream: TStream; const value: TAccountKey): Integer;
begin
  Result := stream.Write(value.EC_OpenSSL_NID, SizeOf(value.EC_OpenSSL_NID));
  Result := Result + WriteAnsiString(stream,value.x);
  Result := Result + WriteAnsiString(stream,value.y);
end;

class function TStreamOp.WriteAnsiString(Stream: TStream; const value: AnsiString): Integer;
Var
  l: Word;
begin
  if (Length(value)>(256*256)) then begin
    TLog.NewLog(lterror,Classname,'Invalid stream size! '+IntToStr(Length(value)));
    raise Exception.Create('Invalid stream size! '+IntToStr(Length(value)));
  end;

  l := Length(value);
  Stream.Write(l, 2);
  if (l > 0) then
    Stream.WriteBuffer(value[1], Length(value));
  Result := l+2;
end;

end.
