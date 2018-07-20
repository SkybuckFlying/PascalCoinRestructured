unit UPlatform;

interface

uses
  UTickCount;

type
  TPlatform = Class
  public
    class function GetTickCount : TTickCount;
    class function GetElapsedMilliseconds(Const previousTickCount : TTickCount) : Int64;
  End;

implementation

{$IFNDEF FPC}
Uses windows;
{$ENDIF}

{ TPlatform }
class function TPlatform.GetElapsedMilliseconds(const previousTickCount: TTickCount): Int64;
begin
  Result := (Self.GetTickCount - previousTickCount);
end;

class function TPlatform.GetTickCount: TTickCount;
begin
  Result := {$IFDEF CPU64}GetTickCount64{$ELSE}{$IFNDEF FPC}Windows.{$ELSE}SysUtils.{$ENDIF}GetTickCount{$ENDIF};
end;

end.
