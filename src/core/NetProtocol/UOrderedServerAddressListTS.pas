unit UOrderedServerAddressListTS;

interface

//uses
//  UNetData; // third circular unit references, saving to git.

uses
  UThread, Classes, UNetConnection, UNodeServerAddress, UNetStatistics;

type
  // This will maintain a list sorted by 2 values: ip/port and netConnection in thread safe mode
  // Using this object, NodeServerAddress can be more high in length and also more quick to search

  { TOrderedServerAddressListTS }
  TOrderedServerAddressListTS = Class
  private
    FAllowDeleteOnClean: Boolean;
    FNetStatistics : PNetStatistics;
    FCritical : TPCCriticalSection;
    FListByIp : TList;
    FListByNetConnection : TList;
    Procedure SecuredDeleteFromListByIp(index : Integer);
    Function SecuredFindByIp(const ip : AnsiString; port : Word; var Index: Integer): Boolean;
    Function SecuredFindByNetConnection(const search : TNetConnection; var Index: Integer): Boolean;
  protected
    function DeleteNetConnection(netConnection : TNetConnection) : Boolean;
  public
    Constructor Create( ParaNetStatistics : PNetStatistics);
    Destructor Destroy; Override;
    Procedure Clear;
    Function Count : Integer;
    Function CleanBlackList(forceCleanAll : Boolean) : Integer;
    procedure CleanNodeServersList;
    Function LockList : TList;
    Procedure UnlockList;
    function IsBlackListed(const ip: AnsiString): Boolean;
    function GetNodeServerAddress(const ip : AnsiString; port:Word; CanAdd : Boolean; var nodeServerAddress : TNodeServerAddress) : Boolean;
    procedure SetNodeServerAddress(const nodeServerAddress : TNodeServerAddress);
    Procedure UpdateNetConnection(netConnection : TNetConnection);
    procedure GetNodeServersToConnnect(maxNodes : Integer; useArray : Boolean; var nsa : TNodeServerAddressArray);
    Function GetValidNodeServers(OnlyWhereIConnected : Boolean; Max : Integer): TNodeServerAddressArray;
    property AllowDeleteOnClean : Boolean read FAllowDeleteOnClean write FAllowDeleteOnClean;
  End;

implementation

uses
  UNetProtocolConst, UTime, SysUtils, ULog, UConst, UPtrInt;

{ TOrderedServerAddressListTS }

function TOrderedServerAddressListTS.CleanBlackList(forceCleanAll : Boolean) : Integer;
Var P : PNodeServerAddress;
  i : Integer;
begin
  CleanNodeServersList;
  // This procedure cleans old blacklisted IPs
  Result := 0;
  FCritical.Acquire;
  Try
    for i := FListByIp.Count - 1 downto 0 do begin
      P := FListByIp[i];
      // Is an old blacklisted IP? (More than 1 hour)
      If (P^.is_blacklisted) AND
        ((forceCleanAll) OR ((P^.last_connection+(CT_LAST_CONNECTION_MAX_MINUTES)) < (UnivDateTimeToUnix(DateTime2UnivDateTime(now))))) then begin
        if (AllowDeleteOnClean) then begin
          SecuredDeleteFromListByIp(i);
        end else begin
          P^.is_blacklisted:=False;
        end;
        inc(Result);
      end;
    end;
  Finally
    FCritical.Release;
  End;

//  if (Result>0) then FNetData.NotifyBlackListUpdated;
//  if (Result>0) then FNetDataNotifyEventsThread.FNotifyOnBlackListUpdated := true;
end;

procedure TOrderedServerAddressListTS.CleanNodeServersList;
var i : Integer;
  nsa : TNodeServerAddress;
  currunixtimestamp : Cardinal;
begin
  If Not (FAllowDeleteOnClean) then Exit;
  currunixtimestamp := UnivDateTimeToUnix(DateTime2UnivDateTime(now));
  FCritical.Acquire;
  Try
    i := FListByIp.Count-1;
    while (i>=0) do begin
      nsa := PNodeServerAddress( FListByIp[i] )^;
      If
      (
        Not (nsa.is_blacklisted)
      ) // Not blacklisted
      And
      (
        (nsa.netConnection = Nil)  // No connection
        OR  // Connected but a lot of time without data...
        (
          (Assigned(nsa.netConnection))
          AND
          (
            (nsa.last_connection + CT_LAST_CONNECTION_MAX_MINUTES) < currunixtimestamp
          )
        )
      )
      And
      (
        (nsa.total_failed_attemps_to_connect>0)
        OR
        (
          // I've not connected CT_LAST_CONNECTION_MAX_MINUTES minutes before
          (
            (nsa.last_connection + CT_LAST_CONNECTION_MAX_MINUTES) < currunixtimestamp
          )
          And // Others have connected CT_LAST_CONNECTION_BY_SERVER_MAX_MINUTES minutes before
          (
            (nsa.last_connection_by_server + CT_LAST_CONNECTION_BY_SERVER_MAX_MINUTES) < currunixtimestamp
          )
          And
          (
            (nsa.last_connection>0) Or (nsa.last_connection_by_server>0)
          )
        )
      )
      And
      (
        (nsa.last_connection_by_me=0)
        Or
        (
          (nsa.last_connection_by_me + 86400) < currunixtimestamp
        )  // Not connected in 24 hours
      )
      then begin
        TLog.NewLog(ltdebug,ClassName,Format('Delete node server address: %s : %d last_connection:%d last_connection_by_server:%d total_failed_attemps:%d last_attempt_to_connect:%s ',
          [nsa.ip,nsa.port,nsa.last_connection,nsa.last_connection_by_server,nsa.total_failed_attemps_to_connect,FormatDateTime('dd/mm/yyyy hh:nn:ss',nsa.last_attempt_to_connect)]));
        SecuredDeleteFromListByIp(i);
      end;
      dec(i);
    end;
  finally
    FCritical.Release;
  end;
end;

procedure TOrderedServerAddressListTS.Clear;
Var P : PNodeServerAddress;
  i : Integer;
begin
  FCritical.Acquire;
  Try
    for i := 0 to FListByIp.Count - 1 do begin
      P := FListByIp[i];
      Dispose(P);
    end;
//    inc(FNetData.FNetStatistics.NodeServersDeleted,FListByIp.count); // ** FIX **
    FListByIp.Clear;
    FListByNetConnection.Clear;
//    FNetData.FNetStatistics.NodeServersListCount := 0; // ** FIX **
  finally
    FCritical.Release;
  end;
end;

function TOrderedServerAddressListTS.Count: Integer;
begin
  FCritical.Acquire;
  try
    Result := FListByIp.Count;
  finally
    FCritical.Release;
  end;
end;

constructor TOrderedServerAddressListTS.Create( ParaNetStatistics : PNetStatistics );
begin
  FNetStatistics := ParaNetStatistics;
  FCritical := TPCCriticalSection.Create(Classname);
  FListByIp := TList.Create;
  FListByNetConnection := TList.Create;
  FAllowDeleteOnClean := True;
end;

function TOrderedServerAddressListTS.DeleteNetConnection(netConnection: TNetConnection) : Boolean;
Var i : Integer;
begin
  FCritical.Acquire;
  Try
    If SecuredFindByNetConnection(netConnection,i) then begin
      PNodeServerAddress( FListByNetConnection[i] )^.netConnection := Nil;
      FListByNetConnection.Delete(i);
      Result := True;
    end else Result := False;
  Finally
    FCritical.Release;
  end;
end;

destructor TOrderedServerAddressListTS.Destroy;
begin
  Clear;
  FreeAndNil(FCritical);
  FreeAndNil(FListByIp);
  FreeAndNil(FListByNetConnection);
  inherited Destroy;
end;

function TOrderedServerAddressListTS.GetNodeServerAddress(const ip: AnsiString; port: Word; CanAdd: Boolean; var nodeServerAddress: TNodeServerAddress): Boolean;
Var i : Integer;
  P : PNodeServerAddress;
begin
  FCritical.Acquire;
  Try
    if SecuredFindByIp(ip,port,i) then begin
      P := FListByIp.Items[i];
      nodeServerAddress := P^;
      Result := True;
    end else if CanAdd then begin
      New(P);
      P^ := CT_TNodeServerAddress_NUL;
      P^.ip := ip;
      P^.port := port;
      FListByIp.Insert(i,P);
      nodeServerAddress := P^;
      Result := True
    end else begin
      nodeServerAddress := CT_TNodeServerAddress_NUL;
      Result := False;
    end;
  Finally
    FCritical.Release;
  End;
end;

procedure TOrderedServerAddressListTS.GetNodeServersToConnnect(maxNodes: Integer; useArray : Boolean; var nsa: TNodeServerAddressArray);
  Procedure sw(l : TList);
  Var i,j,x,y : Integer;
  begin
    if l.Count<=1 then exit;
    j := Random(l.Count)*3;
    for i := 0 to j do begin
      x := Random(l.Count);
      y := Random(l.Count);
      if x<>y then l.Exchange(x,y);
  end;
  end;
  Function IsValid(Const ns : TNodeServerAddress) : Boolean;
  Begin
    Result := (Not Assigned(ns.netConnection)) AND (Not IsBlackListed(ns.ip)) AND (Not ns.its_myself) And
          ((ns.last_attempt_to_connect=0) Or ((ns.last_attempt_to_connect+EncodeTime(0,3,0,0)<now))) And
          ((ns.total_failed_attemps_to_connect<3) Or (ns.last_attempt_to_connect+EncodeTime(0,10,0,0)<now));
  End;
Var i,j, iStart : Integer;
  P : PNodeServerAddress;
  l : TList;
  ns : TNodeServerAddress;
begin
  SetLength(nsa,0);
  FCritical.Acquire;
  Try
    l := TList.Create;
    Try
      if useArray then begin
        for i := 0 to High(nsa) do begin
          If GetNodeServerAddress(nsa[i].ip,nsa[i].port,true,ns) then begin
            if IsValid(ns) then begin
              new(P);
              P^ := ns;
              l.Add(P);
            end;
          end;
        end;
      end else begin
        if FListByIp.Count>0 then begin
          iStart := Random(FListByIp.Count);
          i := iStart;
          j := FListByIp.Count;
          while (l.Count<maxNodes) And (i<j) do begin
            P := FListByIp[i];
            If (Not Assigned(P.netConnection)) AND (Not IsBlackListed(P^.ip)) AND (Not P^.its_myself) And
              ((P^.last_attempt_to_connect=0) Or ((P^.last_attempt_to_connect+EncodeTime(0,3,0,0)<now))) And
              ((P^.total_failed_attemps_to_connect<3) Or (P^.last_attempt_to_connect+EncodeTime(0,10,0,0)<now)) then begin
              l.Add(P);
            end;
            // Second round
            inc(i);
            if (i>=j) and (iStart>0) then begin
              j := iStart;
              iStart := 0;
              i := 0;
            end;
          end;
        end;
      end;
      if (l.Count>0) then begin
        sw(l);
        if l.Count<maxNodes then setLength(nsa,l.Count)
        else setLength(nsa,maxNodes);
        for i := 0 to high(nsa) do begin
          nsa[i] := PNodeServerAddress(l[i])^;
        end;
      end;
    Finally
      if useArray then begin
        for i := 0 to l.Count - 1 do begin
          P := l[i];
          Dispose(P);
        end;
      end;
      l.Free;
    End;
  Finally
    FCritical.Release;
  end;
end;

function TOrderedServerAddressListTS.GetValidNodeServers(OnlyWhereIConnected: Boolean; Max: Integer): TNodeServerAddressArray;
var i,j,iStart : Integer;
  nsa : TNodeServerAddress;
  currunixtimestamp : Cardinal;
begin
  SetLength(Result,0);
  currunixtimestamp := UnivDateTimeToUnix(DateTime2UnivDateTime(now));
  CleanNodeServersList;
  // Save other node servers
  FCritical.Acquire;
  try
    If Max>0 then iStart := Random(FListByIp.Count)
    else iStart := 0;
    i := iStart;
    j := FListByIp.Count;
    while ((length(Result)<Max) Or (Max<=0)) And (i<j) do begin
      nsa := PNodeServerAddress( FListByIp[i] )^;
      if
      (
        Not IsBlackListed(nsa.ip)
      )
      And
      (
        // I've connected 1h before
        (
          (nsa.last_connection>0)
          And
          (
            (Assigned(nsa.netConnection))
            Or
            (
              (nsa.last_connection + CT_LAST_CONNECTION_MAX_MINUTES) > currunixtimestamp
            )
          )
        )
        Or // Others have connected 3h before
        (
          (nsa.last_connection_by_server>0)
          And
          (
            (nsa.last_connection_by_server + CT_LAST_CONNECTION_BY_SERVER_MAX_MINUTES) > currunixtimestamp
          )
        )
        Or // Peer cache
        (
          (nsa.last_connection=0) And (nsa.last_connection_by_server=0)
        )
      )
      And
      (
        // Never tried to connect or successfully connected
        (nsa.total_failed_attemps_to_connect=0)
      )
      And
      (
        (Not nsa.its_myself) Or (nsa.port=CT_NetServer_Port)
      )
      And
      (
        (Not OnlyWhereIConnected)
        Or
        (nsa.last_connection>0)
      )
      then begin
        SetLength(Result,length(Result)+1);
        Result[high(Result)] := nsa;
      end;
      // Second round
      inc(i);
      if (i>=j) and (iStart>0) then begin
        j := iStart;
        iStart := 0;
        i := 0;
      end;
    end;
  finally
    FCritical.Release;
  end;
end;

function TOrderedServerAddressListTS.IsBlackListed(const ip: AnsiString): Boolean;
Var i : Integer;
  P : PNodeServerAddress;
begin
  Result := false;
  FCritical.Acquire;
  Try
    SecuredFindByIp(ip,0,i);
    // Position will be the first by IP:
    while (i<FListByIp.Count) And (Not Result) do begin
      P := PNodeServerAddress(FListByIp[i]);
      if Not SameStr(P^.ip,ip) then exit;
      if P^.is_blacklisted then begin
        Result := Not P^.its_myself;
      end;
      inc(i);
    end;
  Finally
    FCritical.Release;
  End;
end;

function TOrderedServerAddressListTS.LockList: TList;
begin
  FCritical.Acquire;
  Result := FListByIp;
end;

procedure TOrderedServerAddressListTS.SecuredDeleteFromListByIp(index: Integer);
Var P : PNodeServerAddress;
  i2 : Integer;
begin
  P := FListByIp.Items[index];
  if (Assigned(P^.netConnection)) then begin
    If SecuredFindByNetConnection(P^.netConnection,i2) then begin
      FListByNetConnection.Delete(i2);
    end else TLog.NewLog(ltError,ClassName,'DEV ERROR 20180201-1 NetConnection not found!');
  end;
  Dispose(P);
  FListByIp.Delete(index);
//  dec(FNetData.FNetStatistics.NodeServersListCount); // ** FIX **
//  inc(FNetData.FNetStatistics.NodeServersDeleted); // ** FIX **
end;

function TOrderedServerAddressListTS.SecuredFindByIp(const ip: AnsiString; port: Word; var Index: Integer): Boolean;
var L, H, I, C: Integer;
  PN : PNodeServerAddress;
begin
  Result := False;
  L := 0;
  H := FListByIp.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    PN := FListByIp.Items[I];
    C := CompareStr( PN.ip, ip );
    If (C=0) then begin
      C := PN.port-port;
    end;
    if C < 0 then L := I + 1 else
    begin
      H := I - 1;
      if C = 0 then
      begin
        Result := True;
        L := I;
      end;
    end;
  end;
  Index := L;
end;

function TOrderedServerAddressListTS.SecuredFindByNetConnection(const search: TNetConnection; var Index: Integer): Boolean;
var L, H, I: Integer;
  PN : PNodeServerAddress;
  C : PtrInt;
begin
  Result := False;
  L := 0;
  H := FListByNetConnection.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    PN := FListByNetConnection.Items[I];
    C := PtrInt(PN.netConnection) - PtrInt(search);
    if C < 0 then L := I + 1 else
    begin
      H := I - 1;
      if C = 0 then
      begin
        Result := True;
        L := I;
      end;
    end;
  end;
  Index := L;
end;

procedure TOrderedServerAddressListTS.SetNodeServerAddress(
  const nodeServerAddress: TNodeServerAddress);
Var i : Integer;
  P : PNodeServerAddress;
begin
  FCritical.Acquire;
  Try
    if SecuredFindByIp(nodeServerAddress.ip,nodeServerAddress.port,i) then begin
      P := FListByIp.Items[i];
      if (P^.netConnection<>nodeServerAddress.netConnection) then begin
        // Updated netConnection
        if Assigned(P^.netConnection) then begin
          // Delete old value
          if Not DeleteNetConnection(P^.netConnection) then TLog.NewLog(lterror,Classname,'DEV ERROR 20180205-1');
        end;
      end;
      P^ := nodeServerAddress;
    end else begin
      New(P);
      P^ := nodeServerAddress;
      FListByIp.Insert(i,P);
//      Inc(FNetData.FNetStatistics.NodeServersListCount);  // ** FIX **
      TLog.NewLog(ltdebug,Classname,'Adding new server: '+NodeServerAddress.ip+':'+Inttostr(NodeServerAddress.port));
    end;
    if Assigned(nodeServerAddress.netConnection) then begin
      If Not SecuredFindByNetConnection(nodeServerAddress.netConnection,i) then begin
        FListByNetConnection.Insert(i,P);
      end;
    end;
  Finally
    FCritical.Release;
  end;
end;

procedure TOrderedServerAddressListTS.UnlockList;
begin
  FCritical.Release;
end;

procedure TOrderedServerAddressListTS.UpdateNetConnection(netConnection: TNetConnection);
Var i : Integer;
begin
  FCritical.Acquire;
  Try
    If SecuredFindByNetConnection(netConnection,i) then begin
      PNodeServerAddress(FListByNetConnection[i])^.last_connection := (UnivDateTimeToUnix(DateTime2UnivDateTime(now)));
      PNodeServerAddress(FListByNetConnection[i])^.total_failed_attemps_to_connect := 0;
    end;
  Finally
    FCritical.Release;
  End;
end;


end.
