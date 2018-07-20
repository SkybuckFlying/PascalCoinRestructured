unit UNetworkAdjustedTime;

interface

type
  TNetworkAdjustedTime = Class
  private
    FTimesList : TPCThreadList;
    FTimeOffset : Integer;
    FTotalCounter : Integer;
    Function IndexOfClientIp(list : TList; const clientIp : AnsiString) : Integer;
    Procedure UpdateMedian(list : TList);
  public
    constructor Create;
    destructor Destroy; override;
    procedure UpdateIp(const clientIp : AnsiString; clientTimestamp : Cardinal);
    procedure AddNewIp(const clientIp : AnsiString; clientTimestamp : Cardinal);
    procedure RemoveIp(const clientIp : AnsiString);
    function GetAdjustedTime : Cardinal;
    property TimeOffset : Integer read FTimeOffset;
    function GetMaxAllowedTimestampForNewBlock : Cardinal;
  end;

implementation

{ TNetworkAdjustedTime }

Type TNetworkAdjustedTimeReg = Record
     clientIp : AnsiString; // Client IP allows only 1 connection per IP (not using port)
     timeOffset : Integer;
     counter : Integer; // To prevent a time attack from a single IP with multiple connections, only 1 will be used for calc NAT
   End;
   PNetworkAdjustedTimeReg = ^TNetworkAdjustedTimeReg;

procedure TNetworkAdjustedTime.AddNewIp(const clientIp: AnsiString; clientTimestamp : Cardinal);
Var l : TList;
  i : Integer;
  P : PNetworkAdjustedTimeReg;
begin
  l := FTimesList.LockList;
  try
    i := IndexOfClientIp(l,clientIp);
    if i<0 then begin
      New(P);
      P^.clientIp := clientIp;
      P^.counter := 0;
      l.Add(P);
    end else begin
      P := l[i];
    end;
    P^.timeOffset := clientTimestamp - UnivDateTimeToUnix(DateTime2UnivDateTime(now));
    inc(P^.counter);
    inc(FTotalCounter);
    UpdateMedian(l);
    TLog.NewLog(ltDebug,ClassName,Format('AddNewIp (%s,%d) - Total:%d/%d Offset:%d',[clientIp,clientTimestamp,l.Count,FTotalCounter,FTimeOffset]));
  finally
    FTimesList.UnlockList;
  end;
end;

constructor TNetworkAdjustedTime.Create;
begin
  FTimesList := TPCThreadList.Create('TNetworkAdjustedTime_TimesList');
  FTimeOffset := 0;
  FTotalCounter := 0;
end;

destructor TNetworkAdjustedTime.Destroy;
Var P : PNetworkAdjustedTimeReg;
  i : Integer;
  l : TList;
begin
  l := FTimesList.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      P := l[i];
      Dispose(P);
    end;
    l.Clear;
  finally
    FTimesList.UnlockList;
  end;
  FreeAndNil(FTimesList);
  inherited;
end;

function TNetworkAdjustedTime.GetAdjustedTime: Cardinal;
begin
  Result := UnivDateTimeToUnix(DateTime2UnivDateTime(now)) + FTimeOffset;
end;

function TNetworkAdjustedTime.GetMaxAllowedTimestampForNewBlock: Cardinal;
var l : TList;
begin
  l := FTimesList.LockList;
  try
    Result := (GetAdjustedTime + CT_MaxFutureBlockTimestampOffset);
  finally
    FTimesList.UnlockList;
  end;
end;

function TNetworkAdjustedTime.IndexOfClientIp(list: TList; const clientIp: AnsiString): Integer;
begin
  for Result := 0 to list.Count - 1 do begin
    if AnsiSameStr(PNetworkAdjustedTimeReg(list[result])^.clientIp,clientIp) then exit;
  end;
  Result := -1;
end;

procedure TNetworkAdjustedTime.RemoveIp(const clientIp: AnsiString);
Var l : TList;
  i : Integer;
  P : PNetworkAdjustedTimeReg;
begin
  l := FTimesList.LockList;
  try
    i := IndexOfClientIp(l,clientIp);
    if (i>=0) then begin
      P := l[i];
      Dec(P^.counter);
      if (P^.counter<=0) then begin
        l.Delete(i);
        Dispose(P);
      end;
      Dec(FTotalCounter);
    end;
    UpdateMedian(l);
    if (i>=0) then
      TLog.NewLog(ltDebug,ClassName,Format('RemoveIp (%s) - Total:%d/%d Offset:%d',[clientIp,l.Count,FTotalCounter,FTimeOffset]))
    else TLog.NewLog(ltError,ClassName,Format('RemoveIp not found (%s) - Total:%d/%d Offset:%d',[clientIp,l.Count,FTotalCounter,FTimeOffset]))
  finally
    FTimesList.UnlockList;
  end;
end;

function SortPNetworkAdjustedTimeReg(p1, p2: pointer): integer;
begin
  Result := PNetworkAdjustedTimeReg(p1)^.timeOffset - PNetworkAdjustedTimeReg(p2)^.timeOffset;
end;

procedure TNetworkAdjustedTime.UpdateIp(const clientIp: AnsiString; clientTimestamp: Cardinal);
Var l : TList;
  i : Integer;
  P : PNetworkAdjustedTimeReg;
  lastOffset : Integer;
begin
  l := FTimesList.LockList;
  try
    i := IndexOfClientIp(l,clientIp);
    if i<0 then begin
      TLog.NewLog(ltError,ClassName,Format('UpdateIP (%s,%d) not found',[clientIp,clientTimestamp]));
      exit;
    end else begin
      P := l[i];
    end;
    lastOffset := P^.timeOffset;
    P^.timeOffset := clientTimestamp - UnivDateTimeToUnix(DateTime2UnivDateTime(now));
    if (lastOffset<>P^.timeOffset) then begin
      UpdateMedian(l);
      TLog.NewLog(ltDebug,ClassName,Format('UpdateIp (%s,%d) - Total:%d/%d Offset:%d',[clientIp,clientTimestamp,l.Count,FTotalCounter,FTimeOffset]));
    end;
  finally
    FTimesList.UnlockList;
  end;
end;

procedure TNetworkAdjustedTime.UpdateMedian(list : TList);
Var last : Integer;
  i : Integer;
  s : String;
begin
  last := FTimeOffset;
  list.Sort(SortPNetworkAdjustedTimeReg);
  if list.Count<CT_MinNodesToCalcNAT then begin
    FTimeOffset := 0;
  end else if ((list.Count MOD 2)=0) then begin
    FTimeOffset := (PNetworkAdjustedTimeReg(list[(list.Count DIV 2)-1])^.timeOffset + PNetworkAdjustedTimeReg(list[(list.Count DIV 2)])^.timeOffset) DIV 2;
  end else begin
    FTimeOffset := PNetworkAdjustedTimeReg(list[list.Count DIV 2])^.timeOffset;
  end;
  if (last<>FTimeOffset) then begin
    s := '';
    for i := 0 to list.Count - 1 do begin
      s := s + ',' + IntToStr(PNetworkAdjustedTimeReg(list[i])^.timeOffset);
    end;
    TLog.NewLog(ltinfo,ClassName,
      Format('Updated NAT median offset. My offset is now %d (before %d) based on %d/%d connections %s',[FTimeOffset,last,list.Count,FTotalCounter,s]));
  end;
end;


end.
