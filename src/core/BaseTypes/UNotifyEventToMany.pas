unit UNotifyEventToMany;

interface

uses
  Classes;

// Skybuck: could be moved to Lists folder, seems more like a list to me ;)
type
  TNotifyEventToMany = Class
  private
    FList : Array of TNotifyEvent;
  public
    function IndexOf(search : TNotifyEvent) : Integer;
    procedure Add(newNotifyEvent : TNotifyEvent);
    procedure Remove(removeNotifyEvent : TNotifyEvent);
    procedure Invoke(sender : TObject);
    function Count : Integer;
    procedure Delete(index : Integer);
    Constructor Create;
  End;

implementation

uses
  SysUtils;

{ TNotifyEventToMany }

procedure TNotifyEventToMany.Add(newNotifyEvent: TNotifyEvent);
begin
  if IndexOf(newNotifyEvent)>=0 then exit;
  SetLength(FList,length(FList)+1);
  FList[high(FList)] := newNotifyEvent;
end;

function TNotifyEventToMany.Count: Integer;
begin
  Result := Length(FList);
end;

constructor TNotifyEventToMany.Create;
begin
  SetLength(FList,0);
end;

procedure TNotifyEventToMany.Delete(index: Integer);
Var i : Integer;
begin
  if (index<0) Or (index>High(FList)) then raise Exception.Create('Invalid index '+Inttostr(index)+' in '+Self.ClassName+'.Delete');
  for i := index+1 to high(FList) do begin
    FList[i-1] := FList[i];
  end;
  SetLength(FList,length(FList)-1);
end;

function TNotifyEventToMany.IndexOf(search: TNotifyEvent): Integer;
begin
  for Result := low(FList) to high(FList) do begin
    if (TMethod(FList[Result]).Code = TMethod(search).Code) And
       (TMethod(FList[Result]).Data = TMethod(search).Data) then Exit;
  end;
  Result := -1;
end;

procedure TNotifyEventToMany.Invoke(sender: TObject);
Var i,j : Integer;
begin
  j := -1;
  Try
    for i := low(FList) to high(FList) do begin
      j := i;
      FList[i](sender);
    end;
  Except
    On E:Exception do begin
      E.Message := Format('Error TNotifyManyEventHelper.Invoke %d/%d (%s) %s',[j+1,length(FList),E.ClassType,E.Message]);
      Raise;
    end;
  End;
end;

procedure TNotifyEventToMany.Remove(removeNotifyEvent: TNotifyEvent);
Var i : Integer;
begin
  i := IndexOf(removeNotifyEvent);
  if (i>=0) then begin
    Delete(i);
  end;
end;

end.
