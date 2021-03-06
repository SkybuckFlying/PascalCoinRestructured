unit UNetData;

interface

uses
  Classes, UECPrivateKey, UThread, UOrderedServerAddressListTS, UNetStatistics, UProcessReservedAreaMessage, UNotifyEventToMany,
  UOperationBlock, UNodeServerAddress, UNetWorkAdjustedTime, UNetConnection, UNetHeaderData, UPascalCoinBank;

type
  TNetData = Class
  private
    FNotifyOnReceivedHelloMessage : Boolean;
    FNotifyOnStatisticsChanged : Boolean;
    FNotifyOnNetConnectionsUpdated : Boolean;
    FNotifyOnNodeServersUpdated : Boolean;
    FNotifyOnBlackListUpdated : Boolean;

    FOnReceivedHelloMessage: TNotifyEvent;
    FOnStatisticsChanged: TNotifyEvent;
    FOnNetConnectionsUpdated: TNotifyEvent;
    FOnNodeServersUpdated: TNotifyEvent;
    FOnBlackListUpdated: TNotifyEvent;

    FTerminatedAllConnections : boolean; // Skybuck: moved from DestroyClientsThread to here.
    FMaxNodeServersAddressesBuffer: Integer;
    FMaxServersConnected: Integer;
    FMinServersConnected: Integer;
    FNetDataNotifyEventsThread : TPCCustomThread;
    FNodePrivateKey : TECPrivateKey;
    FNetConnections : TPCThreadList;
    FNodeServersAddresses : TOrderedServerAddressListTS;
    FLastRequestId : Cardinal;
    FOnProcessReservedAreaMessage: TProcessReservedAreaMessage;
    FRegisteredRequests : TPCThreadList;
    FIsDiscoveringServers : Boolean;
    FIsGettingNewBlockChainFromClient : Boolean;
    FOnConnectivityChanged : TNotifyEventToMany;
    FThreadCheckConnections : TPCCustomThread;
    FNetStatistics: TNetStatistics;
    FMaxRemoteOperationBlock : TOperationBlock;
    FFixedServers : TNodeServerAddressArray;
    FNetClientsDestroyThread : TPCCustomThread;
    FNetConnectionsActive: Boolean;
    FMaxConnections : Integer;
    FNetworkAdjustedTime : TNetworkAdjustedTime;
    procedure SetMaxNodeServersAddressesBuffer(AValue: Integer);
    procedure SetMaxServersConnected(AValue: Integer);
    procedure SetMinServersConnected(AValue: Integer);
    procedure SetNetConnectionsActive(const Value: Boolean);  protected
//    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    Procedure DiscoverServersTerminated(Sender : TObject);
  protected

    procedure CheckConnectionsThread( Sender : TObject );

    procedure SynchronizedNotify;
    procedure NotifyEventsThread( Sender : TObject );

    procedure DestroyClientsThread( Sender : TObject );
    procedure WaitForTerminatedAllConnections;
  public

    // Skybuck: moved to here to offer access to UNetServer
    Procedure IncStatistics(incActiveConnections,incClientsConnections,incServersConnections,incServersConnectionsWithResponse : Integer; incBytesReceived, incBytesSend : Int64);

    // Skybuck: moved to here to offer access to UNetConnection
    procedure DoProcessReservedAreaMessage(senderConnection : TNetConnection; const headerData : TNetHeaderData; receivedData : TStream; responseData : TStream); virtual;


    Class function HeaderDataToText(const HeaderData : TNetHeaderData) : AnsiString;
    Class function ExtractHeaderInfo(buffer : TStream; var HeaderData : TNetHeaderData; DataBuffer : TStream; var IsValidHeaderButNeedMoreData : Boolean) : Boolean;
    Class Function OperationToText(operation : Word) : AnsiString;

    //
//    Constructor Create(AOwner : TComponent); override;
    Constructor Create;
    Destructor Destroy; override;
    Function NewRequestId : Cardinal;
    Procedure RegisterRequest(Sender: TNetConnection; operation : Word; request_id : Cardinal);
    Function UnRegisterRequest(Sender: TNetConnection; operation : Word; request_id : Cardinal) : Boolean;
    Function PendingRequest(Sender : TNetConnection; var requests_data : AnsiString ) : Integer;
    Procedure AddServer(NodeServerAddress : TNodeServerAddress);
    //
    Procedure DiscoverFixedServersOnly(const FixedServers : TNodeServerAddressArray);
    //
    Function ConnectionsCountAll : Integer;
    Function ConnectionsCountServerClients : Integer;
    Function ConnectionsCountClients : Integer;
    Function GetConnection(index : Integer; var NetConnection : TNetConnection) : Boolean;
    Function ConnectionsCount(CountOnlyNetClients : Boolean) : Integer;
    Function Connection(index : Integer) : TNetConnection;
    Function ConnectionExistsAndActive(ObjectPointer : TObject) : Boolean;
    Function ConnectionExists(ObjectPointer : TObject) : Boolean;
    Function ConnectionLock(Sender : TObject; ObjectPointer : TObject; MaxWaitMiliseconds : Cardinal) : Boolean;
    Procedure ConnectionUnlock(ObjectPointer : TObject);
    Function FindConnectionByClientRandomValue(Sender : TNetConnection) : TNetConnection;
    Procedure DiscoverServers;
    Procedure DisconnectClients;
    Procedure GetNewBlockChainFromClient(Connection : TNetConnection; const why : String);
    Property NodeServersAddresses : TOrderedServerAddressListTS read FNodeServersAddresses;
    Property NetConnections : TPCThreadList read FNetConnections;
    Property NetStatistics : TNetStatistics read FNetStatistics;
    Property IsDiscoveringServers : Boolean read FIsDiscoveringServers;
    Property IsGettingNewBlockChainFromClient : Boolean read FIsGettingNewBlockChainFromClient;
    Property MaxRemoteOperationBlock : TOperationBlock read FMaxRemoteOperationBlock write FMaxRemoteOperationBlock; // Skybuck: write propery added for UThreadGetNewBlockChainFromClient
    Property NodePrivateKey : TECPrivateKey read FNodePrivateKey;
    property OnConnectivityChanged : TNotifyEventToMany read FOnConnectivityChanged;
    Property OnNetConnectionsUpdated : TNotifyEvent read FOnNetConnectionsUpdated write FOnNetConnectionsUpdated;
    Property OnNodeServersUpdated : TNotifyEvent read FOnNodeServersUpdated write FOnNodeServersUpdated;
    Property OnBlackListUpdated : TNotifyEvent read FOnBlackListUpdated write FOnBlackListUpdated;
    Property OnReceivedHelloMessage : TNotifyEvent read FOnReceivedHelloMessage write FOnReceivedHelloMessage;
    Property OnStatisticsChanged : TNotifyEvent read FOnStatisticsChanged write FOnStatisticsChanged;
    procedure NotifyConnectivityChanged;
    Procedure NotifyNetConnectionUpdated;
    Procedure NotifyNodeServersUpdated;
    Procedure NotifyBlackListUpdated;
    Procedure NotifyReceivedHelloMessage;
    Procedure NotifyStatisticsChanged;
    Property NetConnectionsActive : Boolean read FNetConnectionsActive write SetNetConnectionsActive;
    Property NetworkAdjustedTime : TNetworkAdjustedTime read FNetworkAdjustedTime;
    Property MaxNodeServersAddressesBuffer : Integer read FMaxNodeServersAddressesBuffer write SetMaxNodeServersAddressesBuffer;
    Property OnProcessReservedAreaMessage : TProcessReservedAreaMessage read FOnProcessReservedAreaMessage write FOnProcessReservedAreaMessage; // Skybuck: never used ? New feature or left over ?
    Property MinServersConnected : Integer read FMinServersConnected write SetMinServersConnected;
    Property MaxServersConnected : Integer read FMaxServersConnected write SetMaxServersConnected;

    // Skybuck: property added to offer access to UNetServer
    property MaxConnections : Integer read FMaxConnections write FMaxConnections;
  End;

Var
  PascalNetData : TNetData = nil; // Skybuck: another potential global var, investigate later.

implementation

uses
  UNetRequestRegistered, SysUtils, UConst, UTime, UNetProtocolConst, UNode, UNetClient, UNetServerClient, ULog, UPtrInt, UThreadDiscoverConnection,
  UThreadGetNewBlockChainFromClient, UNetTransferType, UStreamOp, UAccountComp, UPCOperationsComp, UPascalCoinSafeBox, UOperationsHashTree, UOperationsResumeList,
  UBlockAccount, URawBytes, UPCSafeBoxHeader, UPCChunk, UCrypto, UTickCount, UPlatform;

Type PNetRequestRegistered = ^TNetRequestRegistered;

function SortNodeServerAddress(Item1, Item2: Pointer): Integer;
Var P1,P2 : PNodeServerAddress;
Begin
  P1 := Item1;
  P2 := Item2;
  Result := AnsiCompareText(P1.ip,P2.ip);
  if Result=0 then Result := P1.port - P2.port;
End;

procedure TNetData.AddServer(NodeServerAddress: TNodeServerAddress);
Var P : PNodeServerAddress;
  i : Integer;
  l : TList;
  currunixtimestamp : Cardinal;
  nsa : TNodeServerAddress;
begin
  if trim(NodeServerAddress.ip)='' then exit;

  if (NodeServerAddress.port<=0) then NodeServerAddress.port := CT_NetServer_Port
  else if (NodeServerAddress.port<>CT_NetServer_Port) then exit;

  // Protection against fill with invalid nodes
  currunixtimestamp := UnivDateTimeToUnix(DateTime2UnivDateTime(now));
  // If not connected CT_LAST_CONNECTION_MAX_MINUTES minutes ago...
  If (NodeServerAddress.last_connection_by_server=0) AND (NodeServerAddress.last_connection>0) AND ((NodeServerAddress.last_connection + (CT_LAST_CONNECTION_MAX_MINUTES)) < (currunixtimestamp)) then exit;
  // If not connected CT_LAST_CONNECTION_BY_SERVER_MAX_MINUTES minutes ago...
  If (NodeServerAddress.last_connection=0) AND (NodeServerAddress.last_connection_by_server>0) AND ((NodeServerAddress.last_connection_by_server + (CT_LAST_CONNECTION_BY_SERVER_MAX_MINUTES)) < (currunixtimestamp)) then exit;
  If (NodeServerAddress.last_connection_by_server>currunixtimestamp) OR (NodeServerAddress.last_connection>currunixtimestamp) then exit;
  FNodeServersAddresses.GetNodeServerAddress(NodeServerAddress.ip,NodeServerAddress.port,True,nsa);
  if NodeServerAddress.last_connection>nsa.last_connection then nsa.last_connection := NodeServerAddress.last_connection;
  if NodeServerAddress.last_connection_by_server>nsa.last_connection_by_server then nsa.last_connection_by_server := NodeServerAddress.last_connection_by_server;
  if NodeServerAddress.last_attempt_to_connect>nsa.last_attempt_to_connect then nsa.last_attempt_to_connect := NodeServerAddress.last_attempt_to_connect;
  FNodeServersAddresses.SetNodeServerAddress(nsa);

  NotifyNodeServersUpdated;
end;

function TNetData.Connection(index: Integer): TNetConnection;
Var l : TList;
begin
  l := FNetConnections.LockList;
  try
    Result := TNetConnection( l[index] );
  finally
    FNetConnections.UnlockList;
  end;
end;

function TNetData.ConnectionExists(ObjectPointer: TObject): Boolean;
var i : Integer;
  l : TList;
begin
  Result := false;
  l := FNetConnections.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      if TObject(l[i])=ObjectPointer then begin
        Result := true;
        exit;
      end;
    end;
  finally
    FNetConnections.UnlockList;
  end;
end;

function TNetData.ConnectionExistsAndActive(ObjectPointer: TObject): Boolean;
var i : Integer;
  l : TList;
begin
  Result := false;
  l := FNetConnections.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      if TObject(l[i])=ObjectPointer then begin
        Result := (TNetConnection(ObjectPointer).Connected);
        exit;
      end;
    end;
  finally
    FNetConnections.UnlockList;
  end;
end;

function TNetData.ConnectionLock(Sender : TObject; ObjectPointer: TObject; MaxWaitMiliseconds : Cardinal) : Boolean;
var i : Integer;
  l : TList;
  nc : TNetConnection;
begin
  Result := false; nc := Nil;
  l := FNetConnections.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      if (TObject(l[i])=ObjectPointer) then begin
        if (Not (TNetConnection(l[i]).DoFinalizeConnection)) And (TNetConnection(l[i]).Connected) then begin
          nc := TNetConnection(l[i]);
          exit;
        end else exit;
      end;
    end;
  finally
    FNetConnections.UnlockList;
    if Assigned(nc) then begin
      Result := TPCThread.TryProtectEnterCriticalSection(Sender,MaxWaitMiliseconds,nc.FNetLock); // Skybuck: property problem, will move var to public for now.
    end;
  end;
end;

function TNetData.ConnectionsCount(CountOnlyNetClients : Boolean): Integer;
var i : Integer;
  l : TList;
begin
  l := FNetConnections.LockList;
  try
    if CountOnlyNetClients then begin
      Result := 0;
      for i := 0 to l.Count - 1 do begin
    if TObject(l[i]) is TNetClient then inc(Result);
      end;
    end else Result := l.Count;
  finally
    FNetConnections.UnlockList;
  end;
end;

function TNetData.ConnectionsCountAll: Integer;
Var l : TList;
begin
  l := FNetConnections.LockList;
  try
    Result := l.Count;
  finally
    FNetConnections.UnlockList;
  end;
end;

function TNetData.ConnectionsCountClients: Integer;
Var l : TList; i : Integer;
begin
  Result := 0;
  l := FNetConnections.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      if TObject(l[i]) is TNetClient then inc(Result);
    end;
  finally
    FNetConnections.UnlockList;
  end;
end;

function TNetData.ConnectionsCountServerClients: Integer;
Var l : TList; i : Integer;
begin
  Result := 0;
  l := FNetConnections.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      if TObject(l[i]) is TNetServerClient then inc(Result);
    end;
  finally
    FNetConnections.UnlockList;
  end;
end;

procedure TNetData.ConnectionUnlock(ObjectPointer: TObject);
var i : Integer;
  l : TList;
  nc : TNetConnection;
begin
  l := FNetConnections.LockList;
  try
    for i := 0 to l.Count - 1 do begin
      if TObject(l[i])=ObjectPointer then begin
        TNetConnection(l[i]).FNetLock.Release;
        exit;
      end;
    end;
  finally
    FNetConnections.UnlockList;
  end;
  Try
    nc := (ObjectPointer as TNetConnection);
    if (not assigned(nc.FNetLock)) then raise Exception.Create('NetLock object not assigned');
    nc.FNetLock.Release;
  Except
    on E:Exception do begin
      TLog.NewLog(ltError,Classname,'Error unlocking Object '+IntToHex(PtrInt(ObjectPointer),8)+' Errors ('+E.ClassName+'): '+E.Message);
    end;
  End;
  TLog.NewLog(ltDebug,ClassName,'Unlocked a NetLock object out of connections list');
end;

constructor TNetData.Create;
begin
  inherited Create;

  FNotifyOnReceivedHelloMessage := false;
  FNotifyOnStatisticsChanged := false;
  FNotifyOnNetConnectionsUpdated := false;
  FNotifyOnNodeServersUpdated := false;
  FNotifyOnBlackListUpdated := false;

  FOnProcessReservedAreaMessage:=Nil;
  TLog.NewLog(ltInfo,ClassName,'TNetData.Create');
  FMaxConnections := CT_MaxClientsConnected;
  FNetConnectionsActive := true;
  SetLength(FFixedServers,0);
  FMaxRemoteOperationBlock := CT_OperationBlock_NUL;
  FNetStatistics := CT_TNetStatistics_NUL;
  FOnConnectivityChanged := TNotifyEventToMany.Create;
  FOnStatisticsChanged := Nil;
  FOnNetConnectionsUpdated := Nil;
  FOnNodeServersUpdated := Nil;
  FOnBlackListUpdated := Nil;
  FOnReceivedHelloMessage := Nil;
  FIsDiscoveringServers := false;
  FRegisteredRequests := TPCThreadList.Create('TNetData_RegisteredRequests');
  FNodeServersAddresses := TOrderedServerAddressListTS.Create(@FNetStatistics); //  Skybuck: altered, using pointer to act as an object reference
  FLastRequestId := 0;
  FNetConnections := TPCThreadList.Create('TNetData_NetConnections');
  FIsGettingNewBlockChainFromClient := false;
  FNodePrivateKey := TECPrivateKey.Create;
  FNodePrivateKey.GenerateRandomPrivateKey(CT_Default_EC_OpenSSL_NID);
  FThreadCheckConnections := TPCCustomThread.Create( CheckConnectionsThread );
  FNetDataNotifyEventsThread := TPCCustomThread.Create( NotifyEventsThread );
  FNetClientsDestroyThread := TPCCustomThread.Create( DestroyClientsThread );
  FNetworkAdjustedTime := TNetworkAdjustedTime.Create;
  FMaxNodeServersAddressesBuffer:=(CT_MAX_NODESERVERS_BUFFER DIV 2);
  FMinServersConnected:=CT_MinServersConnected;
  FMaxServersConnected:=CT_MaxServersConnected;
  If Not Assigned(PascalNetData) then PascalNetData := Self;
end;

destructor TNetData.Destroy;
Var l : TList;
  i : Integer;
  tdc : TThreadDiscoverConnection;
begin
  TLog.NewLog(ltInfo,ClassName,'TNetData.Destroy START');
  FreeAndNil(FOnConnectivityChanged);
  FOnStatisticsChanged := Nil;
  FOnNetConnectionsUpdated := Nil;
  FOnNodeServersUpdated := Nil;
  FOnBlackListUpdated := Nil;
  FOnReceivedHelloMessage := Nil;

  // First destroy ThreadCheckConnections to prevent a call to "DiscoverServers"
  TLog.NewLog(ltInfo,ClassName,'ThreadCheckConnections terminating...');
  FThreadCheckConnections.Terminate;
  FThreadCheckConnections.WaitFor;
  FreeAndNil(FThreadCheckConnections);

  // Now finish all DiscoverConnection threads
  Repeat
    tdc := TThreadDiscoverConnection( TPCThreadClass.GetThreadByClass(TThreadDiscoverConnection,nil) );
    if Assigned(tdc) then begin
      tdc.FreeOnTerminate := false;
      tdc.Terminate;
      tdc.WaitFor;
      tdc.Free;
      TLog.NewLog(ltInfo,ClassName,'TThreadDiscoverConnection finished');
    end;
  Until Not Assigned(tdc);

  // Closing connections
  l := FNetConnections.LockList;
  Try
    for i := 0 to l.Count - 1 do begin
      TNetConnection(l[i]).Connected := false;
      TNetConnection(l[i]).FinalizeConnection;
    end;
  Finally
    FNetConnections.UnlockList;
  End;

  WaitForTerminatedAllConnections;
  FNetClientsDestroyThread.Terminate;
  FNetClientsDestroyThread.WaitFor;
  FreeAndNil(FNetClientsDestroyThread);

  FreeAndNil(FNodeServersAddresses);
  FreeAndNil(FNetConnections);
  FreeAndNil(FNodePrivateKey);
  FNetDataNotifyEventsThread.Terminate;
  FNetDataNotifyEventsThread.WaitFor;
  FreeAndNil(FNetDataNotifyEventsThread);
  SetLength(FFixedServers,0);
  FreeAndNil(FRegisteredRequests);
  FreeAndNil(FNetworkAdjustedTime);
  inherited;
  if (PascalNetData=Self) then PascalNetData := Nil;
  TLog.NewLog(ltInfo,ClassName,'TNetData.Destroy END');
end;

procedure TNetData.DisconnectClients;
var i : Integer;
  l : TList;
begin
  l := FNetConnections.LockList;
  Try
    for i := l.Count - 1 downto 0 do begin
      if TObject(l[i]) is TNetClient then begin
        TNetClient(l[i]).Connected := false;
        TNetClient(l[i]).FinalizeConnection;
      end;
    end;
  Finally
    FNetConnections.UnlockList;
  End;
end;

procedure TNetData.DiscoverFixedServersOnly(const FixedServers: TNodeServerAddressArray);
Var i : Integer;
begin
  SetLength(FFixedServers,length(FixedServers));
  for i := low(FixedServers) to high(FixedServers) do begin
    FFixedServers[i] := FixedServers[i];
  end;
  for i := low(FixedServers) to high(FixedServers) do begin
    AddServer(FixedServers[i]);
  end;
end;

procedure TNetData.DiscoverServers;
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
Var P : PNodeServerAddress;
  i,j,k : Integer;
  l,lns : TList;
  tdc : TThreadDiscoverConnection;
  canAdd : Boolean;
  nsa : TNodeServerAddressArray;
begin
  if Not FNetConnectionsActive then exit;
  if TPCThread.ThreadClassFound(TThreadDiscoverConnection,nil)>=0 then begin
    TLog.NewLog(ltInfo,ClassName,'Already discovering servers...');
    exit;
  end;
  FNodeServersAddresses.CleanBlackList(False);
  If NetStatistics.ClientsConnections>0 then begin
    j := FMinServersConnected - NetStatistics.ServersConnectionsWithResponse;
  end else begin
    j := FMaxServersConnected - NetStatistics.ServersConnectionsWithResponse;
  end;
  if j<=0 then exit;
  {$IFDEF HIGHLOG}TLog.NewLog(ltDebug,Classname,'Discover servers start process searching up to '+inttostr(j)+' servers');{$ENDIF}
  if (Length(FFixedServers)>0) then begin
    nsa := FFixedServers;
    FNodeServersAddresses.GetNodeServersToConnnect(j,true,nsa);
  end else begin
    SetLength(nsa,0);
    FNodeServersAddresses.GetNodeServersToConnnect(j,false,nsa);
  end;
  if length(nsa)>0 then begin
    TLog.NewLog(ltDebug,Classname,'Start discovering up to '+inttostr(length(nsa))+' servers... (max:'+inttostr(j)+')');
    //
    for i := 0 to high(nsa) do begin
      FIsDiscoveringServers := true;
      tdc := TThreadDiscoverConnection.Create(nsa[i],DiscoverServersTerminated);
    end;
  end;
end;

procedure TNetData.DiscoverServersTerminated(Sender: TObject);
begin
  NotifyNodeServersUpdated;
  if TPCThread.ThreadClassFound(TThreadDiscoverConnection,Nil)>=0 then exit;
  FIsDiscoveringServers := false;
  // If here, discover servers finished, so we can try to get/receive data
  TLog.NewLog(ltDebug,Classname,Format('Discovering servers finished. Now we have %d active connections and %d connections to other servers',
    [ConnectionsCount(false),ConnectionsCount(true)]));
  if TPCThread.ThreadClassFound(TThreadGetNewBlockChainFromClient,nil)>=0 then exit;
  TThreadGetNewBlockChainFromClient.Create;
end;

procedure TNetData.DoProcessReservedAreaMessage(senderConnection : TNetConnection; const headerData: TNetHeaderData; receivedData: TStream; responseData: TStream);
begin
  If Assigned(FOnProcessReservedAreaMessage) then begin
    FOnProcessReservedAreaMessage(Self,senderConnection,headerData,receivedData,responseData);
  end;
end;

class function TNetData.ExtractHeaderInfo(buffer : TStream; var HeaderData : TNetHeaderData; DataBuffer : TStream; var IsValidHeaderButNeedMoreData : Boolean) : Boolean;
Var lastp : Integer;
  c : Cardinal;
  w : Word;
begin
  HeaderData := CT_NetHeaderData;
  Result := false;
  IsValidHeaderButNeedMoreData := false;
  lastp := buffer.Position;
  Try
    if buffer.Size-buffer.Position < 22 then exit;
    buffer.Read(c,4);
    if (c<>CT_MagicNetIdentification) then exit;
    buffer.Read(w,2);
    case w of
      CT_MagicRequest : HeaderData.header_type := ntp_request;
      CT_MagicResponse : HeaderData.header_type := ntp_response;
      CT_MagicAutoSend : HeaderData.header_type := ntp_autosend;
    else
      HeaderData.header_type := ntp_unknown;
      exit;
    end;
    buffer.Read(HeaderData.operation,2);
    buffer.Read(HeaderData.error_code,2);
    buffer.Read(HeaderData.request_id,4);
    buffer.Read(HeaderData.protocol.protocol_version,2);
    buffer.Read(HeaderData.protocol.protocol_available,2);
    buffer.Read(c,4);
    HeaderData.buffer_data_length := c;
    DataBuffer.Size := 0;
    if (c>0) then begin
      if buffer.Size - buffer.Position < c then begin
        IsValidHeaderButNeedMoreData := true;
        {$IFDEF HIGHLOG}
        TLog.NewLog(ltdebug,className,Format('Need more data! Buffer size (%d) - position (%d) < %d - Header info: %s',
          [buffer.Size,buffer.Position,c,HeaderDataToText(HeaderData)]));
        {$ENDIF}
        exit;
      end;
      DataBuffer.CopyFrom(buffer,c);
      DataBuffer.Position := 0;
    end;
    //
    if HeaderData.header_type=ntp_response then begin
      HeaderData.is_error := HeaderData.error_code<>0;
      if HeaderData.is_error then begin
        TStreamOp.ReadAnsiString(DataBuffer,HeaderData.error_text);
      end;
    end else begin
      HeaderData.is_error := HeaderData.error_code<>0;
      if HeaderData.is_error then begin
        TStreamOp.ReadAnsiString(DataBuffer,HeaderData.error_text);
      end;
    end;
    if (HeaderData.is_error) then begin
      TLog.NewLog(lterror,Classname,'Response with error ('+IntToHex(HeaderData.error_code,4)+'): '+HeaderData.error_text+' ...on '+
        'operation: '+OperationToText(HeaderData.operation)+' id: '+Inttostr(HeaderData.request_id));
    end;
    Result := true;
  Finally
    if Not Result then buffer.Position := lastp;
  End;
end;

function TNetData.FindConnectionByClientRandomValue(Sender: TNetConnection): TNetConnection;
Var l : TList;
  i : Integer;
begin
  l := FNetConnections.LockList;
  try
    for i := 0 to L.Count - 1 do begin
      Result := TNetConnection( l[i] );
      If TAccountComp.EqualAccountKeys(Result.ClientPublicKey,Sender.ClientPublicKey) And (Sender<>Result) then exit;
    end;
  finally
    FNetConnections.UnlockList;
  end;
  Result := Nil;
end;

function TNetData.GetConnection(index: Integer; var NetConnection : TNetConnection) : Boolean;
Var l : TList;
begin
  Result := false; NetConnection := Nil;
  l := FNetConnections.LockList;
  try
    if (index>=0) And (index<l.Count) then begin
      NetConnection := TNetConnection( l[index] );
      Result := true;
      exit;
    end;
  finally
    FNetConnections.UnlockList;
  end;
end;

procedure TNetData.GetNewBlockChainFromClient(Connection: TNetConnection;
  const why: String);
Const CT_LogSender = 'GetNewBlockChainFromClient';

  function Do_GetOperationsBlock( block_start,block_end, MaxWaitMilliseconds : Cardinal; OnlyOperationBlock : Boolean; BlocksList : TList) : Boolean;
  Var SendData,ReceiveData : TMemoryStream;
    headerdata : TNetHeaderData;
    op : TPCOperationsComp;
    request_id,opcount,i, last_n_block : Cardinal;
    errors : AnsiString;
    noperation : Integer;
  begin
    Result := false;
    BlocksList.Clear;
    // First receive operations from
    SendData := TMemoryStream.Create;
    ReceiveData := TMemoryStream.Create;
    try
      if OnlyOperationBlock then begin
        noperation := CT_NetOp_GetBlockHeaders;
      end else begin
        noperation := CT_NetOp_GetBlocks;
      end;
      TLog.NewLog(ltdebug,CT_LogSender,Format('Sending %s from block %d to %d (Total: %d)',
        [TNetData.OperationToText(noperation),block_start,block_end,block_end-block_start+1]));
      SendData.Write(block_start,4);
      SendData.Write(block_end,4);
      request_id := PascalNetData.NewRequestId;
      if Connection.DoSendAndWaitForResponse(noperation,request_id,SendData,ReceiveData,MaxWaitMilliseconds,headerdata) then begin
        if HeaderData.is_error then exit;
        if ReceiveData.Read(opcount,4)<4 then exit; // Error in data
        i := 0; last_n_block := 0;
        while (i<opcount) do begin
          // decode data
          op := TPCOperationsComp.Create;
          If op.LoadBlockFromStream(ReceiveData,errors) then begin
            // Build 2.1.7 Protection for invalid block number
            If ((i>0) And (last_n_block>=op.OperationBlock.block)) Or
               ((Not OnlyOperationBlock) And
                 ( ((i=0) And (op.OperationBlock.block<>block_start))
                   Or
                   ((i>0) And (op.OperationBlock.block<>last_n_block+1)) ) ) then begin
              Connection.DisconnectInvalidClient(false,Format('Invalid block sequence received last:%d received:%d',[last_n_block,op.OperationBlock.block]));
              op.free;
              break;
            end else BlocksList.Add(op);
            last_n_block := op.OperationBlock.block;
          end else begin
            Connection.DisconnectInvalidClient(false,Format('Error reading OperationBlock from received stream %d/%d: %s',[i+1,opcount,errors]));
            op.free;
            break;
          end;
          inc(i);
        end;
        Result := true;
      end else begin
        TLog.NewLog(lterror,CT_LogSender,Format('No received response after waiting %d request id %d operation %s',[MaxWaitMilliseconds,request_id,TNetData.OperationToText(noperation)]));
      end;
    finally
      SendData.Free;
      ReceiveData.free;
    end;
  end;

  function Do_GetOperationBlock(block, MaxWaitMilliseconds : Cardinal; var OperationBlock : TOperationBlock) : Boolean;
  Var BlocksList : TList;
    i : Integer;
  begin
    OperationBlock := CT_OperationBlock_NUL;
    BlocksList := TList.Create;
    try
      Result := Do_GetOperationsBlock(block,block,MaxWaitMilliseconds,True,BlocksList);
      // Build 2.1.7 - Included protection agains not good block received
      if (Result) And (BlocksList.Count=1) then begin
        OperationBlock := TPCOperationsComp(BlocksList[0]).OperationBlock;
        If OperationBlock.block<>block then Result := False;
      end else begin
        Result := False;
      end;
    finally
      for i := 0 to BlocksList.Count - 1 do TPCOperationsComp(BlocksList[i]).Free;
      BlocksList.Free;
    end;
  end;

  Function FindLastSameBlockByOperationsBlock(min,max : Cardinal; var OperationBlock : TOperationBlock) : Boolean;
  var i : Integer;
    ant_nblock : Int64;
    auxBlock, sbBlock : TOperationBlock;
    distinctmax,distinctmin : Cardinal;
    BlocksList : TList;
    errors : AnsiString;
  Begin
    Result := false;
    OperationBlock := CT_OperationBlock_NUL;
    repeat
      BlocksList := TList.Create;
      try
        // *** OperationsComp PROBLEM ***
        // Skybuck: *** Do_GetOperationsBlock MAY HAVE TO BE DONE DIFFERENT, currently it will be applied to PascalCoinBank Directly ! ***
        If Not Do_GetOperationsBlock(min,max,5000,true,BlocksList) then exit;

        if (BlocksList.Count=0) then begin
          Connection.DisconnectInvalidClient(false,'No received info for blocks from '+inttostr(min)+' to '+inttostr(max));
          exit;
        end;
        distinctmin := min;
        distinctmax := max;
        ant_nblock := -1;
        for i := 0 to BlocksList.Count - 1 do begin
          auxBlock := TPCOperationsComp(BlocksList[i]).OperationBlock;
          // Protection of invalid clients:
          if (auxBlock.block<min) Or (auxBlock.block>max) Or (auxBlock.block=ant_nblock) then begin
            Connection.DisconnectInvalidClient(false,'Invalid response... '+inttostr(min)+'<'+inttostr(auxBlock.block)+'<'+inttostr(max)+' ant:'+inttostr(ant_nblock));
            exit;
          end;
          // New Build 2.1.7 - Check valid operationblock
          If Not TPCSafeBox.IsValidOperationBlock(auxBlock,errors) then begin
            Connection.DisconnectInvalidClient(false,'Received invalid operation block searching '+TPCOperationsComp.OperationBlockToText(auxBlock)+' errors: '+errors);
            Exit;
          end;

          ant_nblock := auxBlock.block;
          //
          sbBlock := PascalCoinSafeBox.Block(auxBlock.block).blockchainInfo;
          if TPCOperationsComp.EqualsOperationBlock(sbBlock,auxBlock) then begin
            distinctmin := auxBlock.block;
            OperationBlock := auxBlock;
          end else begin
            if auxBlock.block<=distinctmax then
              distinctmax := auxBlock.block-1;
          end;
        end;
        min := distinctmin;
        max := distinctmax;
      finally
        for i := 0 to BlocksList.Count - 1 do begin
          TPCOperationsComp(BlocksList[i]).Free;
        end;
        BlocksList.Free;
      end;
    until (distinctmin=distinctmax);
    Result := (OperationBlock.proof_of_work <> CT_OperationBlock_NUL.proof_of_work);
  End;

  procedure GetNewBank(start_block : Int64);
  Var BlocksList : TList;
    i : Integer;
    OpComp,OpExecute : TPCOperationsComp;
    oldBlockchainOperations : TOperationsHashTree;
    opsResume : TOperationsResumeList;
    newBlock : TBlockAccount;
    errors : AnsiString;
    start,start_c : Cardinal;
    finished : Boolean;
    Bank : TPCBank;
    ms : TMemoryStream;
    IsAScam, IsUsingSnapshot : Boolean;
  Begin
    IsAScam := false;
    TLog.NewLog(ltdebug,CT_LogSender,Format('GetNewBank(new_start_block:%d)',[start_block]));
    Bank := TPCBank.Create;
    try
      Bank.StorageClass := PascalCoinBank.StorageClass;
      Bank.Storage.Orphan := PascalCoinBank.Storage.Orphan;
      Bank.Storage.ReadOnly := true;
      Bank.Storage.CopyConfiguration(PascalCoinBank.Storage);
      if start_block>=0 then begin
        If (PascalCoinSafeBox.HasSnapshotForBlock(start_block-1)) then begin
          // Restore from a Snapshot (New on V3) instead of restore reading from File
          // Skybuck: make new safebox later *** PROBLEM ***
//          Bank.SafeBox.SetToPrevious(PascalCoinBank.SafeBox,start_block-1);
          Bank.UpdateValuesFromSafebox;
          IsUsingSnapshot := True;
        end else begin
          // Restore a part from disk
          Bank.DiskRestoreFromOperations(start_block-1);

          // Skybuck: *** more problems ***
{
          if (Bank.BlocksCount<start_block) then begin
            TLog.NewLog(lterror,CT_LogSender,Format('No blockchain found start block %d, current %d',[start_block-1,Bank.BlocksCount]));
            start_block := Bank.BlocksCount;
          end;
}
          IsUsingSnapshot := False;
        end;
        start := start_block;
      end else begin
        start := 0;
        start_block := 0;
      end;
      start_c := start;
      Bank.Storage.Orphan := FormatDateTime('yyyymmddhhnnss',DateTime2UnivDateTime(now));
      Bank.Storage.ReadOnly := false;
      // Receive new blocks:
      finished := false;
      // *** PROBLEMS ***
{
      repeat
}
        BlocksList := TList.Create;
        try
          // *** OperationsComp PROBLEM ***
          // Skybuck: *** Do_GetOperationsBlock will have to be done different, currently it's applied to PascalCoinBank instead of Bank
          finished := NOT Do_GetOperationsBlock(start,start + 50,30000,false,BlocksList);


          i := 0;
          while (i<BlocksList.Count) And (Not finished) do begin
            OpComp := TPCOperationsComp(BlocksList[i]);
            ms := TMemoryStream.Create;

            // *** OperationsComp PROBLEM ***
            // Skybuck: some more danger/bugs here, OpExecute applied to PascalCoinBank instead of Bank
            OpExecute := TPCOperationsComp.Create;
            try
              OpComp.SaveBlockToStream(false,ms);
              ms.Position := 0;

              // *** MORE PROBLEMS COOL ***
{
              If not OpExecute.LoadBlockFromStream(ms,errors) then begin
                Connection.DisconnectInvalidClient(false,'Invalid block stream received for block '+IntToStr(Bank.BlocksCount)+' errors: '+errors );
                finished := true;
                IsAScam := true;
                break;
              end;
}
              if Bank.AddNewBlockChainBlock(OpExecute,PascalNetData.NetworkAdjustedTime.GetMaxAllowedTimestampForNewBlock,newBlock,errors) then begin
                inc(i);
              end else begin
                TLog.NewLog(lterror,CT_LogSender,'Error creating new bank with client Operations. Block:'+TPCOperationsComp.OperationBlockToText(OpExecute.OperationBlock)+' Error:'+errors);
                // Add to blacklist !
                Connection.DisconnectInvalidClient(false,'Invalid BlockChain on Block '+TPCOperationsComp.OperationBlockToText(OpExecute.OperationBlock)+' with errors:'+errors);
                finished := true;
                IsAScam := true;
                break;
              end;
            finally
              ms.Free;
              OpExecute.Free;
            end;
          end;
        finally
          for i := 0 to BlocksList.Count - 1 do TPCOperationsComp(BlocksList[i]).Free;
          BlocksList.Free;
        end;

        // *** MORE PROBLEMS COOL ***
{
        start := Bank.BlocksCount;
      until (Bank.BlocksCount=Connection.RemoteOperationBlock.block+1) Or (finished)
        // Allow to do not download ALL new blockchain in a separate folder, only needed blocks!
        Or (Bank.SafeBox.WorkSum > (PascalCoinSafeBox.WorkSum + $FFFFFFFF) );
}

(*
      // New Build 1.5 more work vs more high
      // work = SUM(target) of all previous blocks (Int64)
      // -----------------------------
      // Before of version 1.5 was: "if Bank.BlocksCount>PascalCoinBank.BlocksCount then ..."
      // Starting on version 1.5 is: "if Bank.WORK > MyBank.WORK then ..."
      if Bank.SafeBox.WorkSum > PascalCoinSafeBox.WorkSum then begin
        oldBlockchainOperations := TOperationsHashTree.Create;
        try
          PascalCoinNode.DisableNewBlocks;
          Try
            // I'm an orphan blockchain...
            TLog.NewLog(ltinfo,CT_LogSender,'New valid blockchain found. My block count='+inttostr(PascalCoinBank.BlocksCount)+' work: '+IntToStr(PascalCoinSafeBox.WorkSum)+
              ' found count='+inttostr(Bank.BlocksCount)+' work: '+IntToStr(Bank.SafeBox.WorkSum)+' starting at block '+inttostr(start_block));
            if PascalCoinBank.BlocksCount>0 then begin
              OpExecute := TPCOperationsComp.Create;
              try
                for start:=start_c to PascalCoinBank.BlocksCount-1 do begin
                  If PascalCoinBank.LoadOperations(OpExecute,start) then begin
                    if (OpExecute.Count>0) then begin
                      for i:=0 to OpExecute.Count-1 do begin
                        // TODO: NEED TO EXCLUDE OPERATIONS ALREADY INCLUDED IN BLOCKCHAIN?
                        oldBlockchainOperations.AddOperationToHashTree(OpExecute.Operation[i]);
                      end;
                      TLog.NewLog(ltInfo,CT_LogSender,'Recovered '+IntToStr(OpExecute.Count)+' operations from block '+IntToStr(start));
                    end;
                  end else begin
                    TLog.NewLog(ltError,CT_LogSender,'Fatal error: Cannot read block '+IntToStr(start));
                  end;
                end;
              finally
                OpExecute.Free;
              end;
            end;
            PascalCoinBank.Storage.MoveBlockChainBlocks(start_block,Inttostr(start_block)+'_'+FormatDateTime('yyyymmddhhnnss',DateTime2UnivDateTime(now)),Nil);
            Bank.Storage.MoveBlockChainBlocks(start_block,PascalCoinBank.Storage.Orphan,PascalCoinBank.Storage);
            //
            If IsUsingSnapshot then begin
              TLog.NewLog(ltInfo,CT_LogSender,'Commiting new chain to Safebox');
              Bank.SafeBox.CommitToPrevious;
              Bank.UpdateValuesFromSafebox;
              {$IFDEF Check_Safebox_Names_Consistency}
              If Not Check_Safebox_Names_Consistency(Bank.SafeBox,'Commited',errors) then begin
                TLog.NewLog(lterror,CT_LogSender,'Fatal safebox consistency error getting bank at block '+IntTosTr(start_block)+' : '+errors);
                Sleep(1000);
                halt(0);
              end;
              {$ENDIF}
            end else begin
              TLog.NewLog(ltInfo,CT_LogSender,'Restoring modified Safebox from Disk');
              PascalCoinBank.DiskRestoreFromOperations(CT_MaxBlock);
            end;
          Finally
            PascalCoinNode.EnableNewBlocks;
          End;
          PascalCoinNode.NotifyBlocksChanged;
          // Finally add new operations:
          // Rescue old operations from old blockchain to new blockchain
          If oldBlockchainOperations.OperationsCount>0 then begin
            TLog.NewLog(ltInfo,CT_LogSender,Format('Executing %d operations from block %d to %d',
             [oldBlockchainOperations.OperationsCount,start_c,PascalCoinBank.BlocksCount-1]));
            opsResume := TOperationsResumeList.Create;
            Try
              // Re-add orphaned operations back into the pending pool.
              // NIL is passed as senderConnection since localnode is considered
              // the origin, and current sender needs these operations.
              i := PascalCoinNode.AddOperations(NIL,oldBlockchainOperations,opsResume,errors);
              TLog.NewLog(ltInfo,CT_LogSender,Format('Executed %d/%d operations. Returned errors: %s',[i,oldBlockchainOperations.OperationsCount,errors]));
            finally
              opsResume.Free;
            end;
          end else TLog.NewLog(ltInfo,CT_LogSender,Format('No operations from block %d to %d',[start_c,PascalCoinBank.BlocksCount-1]));
        finally
          oldBlockchainOperations.Free;
        end;
      end else begin
        if (Not IsAScam) And (Connection.RemoteAccumulatedWork > PascalCoinSafeBox.WorkSum) then begin
          // Possible scammer!
          Connection.DisconnectInvalidClient(false,Format('Possible scammer! Says blocks:%d Work:%d - Obtained blocks:%d work:%d',
            [Connection.RemoteOperationBlock.block+1,Connection.RemoteAccumulatedWork,
             Bank.BlocksCount,Bank.SafeBox.WorkSum]));
        end;
      end;
    // *** BIG FAT PROBLEMS COOL ***
    *)

    finally
      Bank.Free;
    end;
  End;

  Function DownloadSafeBoxChunk(safebox_blockscount : Cardinal; Const sbh : TRawBytes; from_block, to_block : Cardinal; receivedDataUnzipped : TStream;
    var safeBoxHeader : TPCSafeBoxHeader; var errors : AnsiString) : Boolean;
  Var sendData,receiveData : TStream;
    headerdata : TNetHeaderData;
    request_id : Cardinal;
    c : Cardinal;
  Begin
    Result := False;
    sendData := TMemoryStream.Create;
    receiveData := TMemoryStream.Create;
    try
      sendData.Write(safebox_blockscount,SizeOf(safebox_blockscount)); // 4 bytes for blockcount
      TStreamOp.WriteAnsiString(SendData,sbh);
      sendData.Write(from_block,SizeOf(from_block));
      c := to_block;
      if (c>=safebox_blockscount) then c := safebox_blockscount-1;
      sendData.Write(c,SizeOf(c));
      if (from_block>c) or (c>=safebox_blockscount) then begin
        errors := 'ERROR DEV 20170727-1';
        Exit;
      end;
      TLog.NewLog(ltDebug,CT_LogSender,Format('Call to GetSafeBox from blocks %d to %d of %d',[from_block,c,safebox_blockscount]));
      request_id := PascalNetData.NewRequestId;
      if Connection.DoSendAndWaitForResponse(CT_NetOp_GetSafeBox,request_id,sendData,receiveData,30000,headerdata) then begin
        if HeaderData.is_error then exit;
        receivedDataUnzipped.Size:=0;
        If Not TPCChunk.LoadSafeBoxFromChunk(receiveData,receivedDataUnzipped,safeBoxHeader,errors) then begin
          Connection.DisconnectInvalidClient(false,'Invalid received chunk: '+errors);
          exit;
        end;
        If (safeBoxHeader.safeBoxHash<>sbh) or (safeBoxHeader.startBlock<>from_block) or (safeBoxHeader.endBlock<>c) or
          (safeBoxHeader.blocksCount<>safebox_blockscount) or (safeBoxHeader.protocol<CT_PROTOCOL_2) or
          (safeBoxHeader.protocol>CT_BlockChain_Protocol_Available) then begin
          errors := Format('Invalid received chunk based on call: Blockscount:%d %d - from:%d %d to %d %d - SafeboxHash:%s %s',
              [safeBoxHeader.blocksCount,safebox_blockscount,safeBoxHeader.startBlock,from_block,safeBoxHeader.endBlock,c,
               TCrypto.ToHexaString(safeBoxHeader.safeBoxHash),TCrypto.ToHexaString(sbh)]);
          Connection.DisconnectInvalidClient(false,'Invalid received chunk: '+errors);
          exit;
        end;
        Result := True;
      end else errors := 'No response on DownloadSafeBoxChunk';
    finally
      receiveData.Free;
      SendData.Free;
    end;
  end;

  Type TSafeBoxChunkData = Record
    safeBoxHeader : TPCSafeBoxHeader;
    chunkStream : TStream;
  end;

  Function DownloadSafeBox(IsMyBlockchainValid : Boolean) : Boolean;
  Var _blockcount,request_id : Cardinal;
    receiveData, receiveChunk, chunk1 : TStream;
    op : TOperationBlock;
    safeBoxHeader : TPCSafeBoxHeader;
    errors : AnsiString;
    chunks : Array of TSafeBoxChunkData;
    i : Integer;
  Begin
    Result := False;
    // Will try to download penultimate saved safebox
    _blockcount := ((Connection.RemoteOperationBlock.block DIV CT_BankToDiskEveryNBlocks)-1) * CT_BankToDiskEveryNBlocks;
    If not Do_GetOperationBlock(_blockcount,5000,op) then begin
      Connection.DisconnectInvalidClient(false,Format('Cannot obtain operation block %d for downloading safebox',[_blockcount]));
      exit;
    end;
    // New Build 2.1.7 - Check valid operationblock
    If Not TPCSafeBox.IsValidOperationBlock(op,errors) then begin
      Connection.DisconnectInvalidClient(false,'Invalid operation block at DownloadSafeBox '+TPCOperationsComp.OperationBlockToText(op)+' errors: '+errors);
      Exit;
    end;
    receiveData := TMemoryStream.Create;
    try
      SetLength(chunks,0);
      try
        // Will obtain chunks of 10000 blocks each
        for i:=0 to ((_blockcount-1) DIV 10000) do begin // Bug v3.0.1 and minors
          receiveChunk := TMemoryStream.Create;
          if (Not DownloadSafeBoxChunk(_blockcount,op.initial_safe_box_hash,(i*10000),((i+1)*10000)-1,receiveChunk,safeBoxHeader,errors)) then begin
            receiveChunk.Free;
            TLog.NewLog(ltError,CT_LogSender,errors);
            Exit;
          end;
          SetLength(chunks,length(chunks)+1);
          chunks[High(chunks)].safeBoxHeader := safeBoxHeader;
          chunks[High(chunks)].chunkStream := receiveChunk;
        end;
        // Will concat safeboxs:
        chunk1 := TMemoryStream.Create;
        try
          if (length(chunks)=1) then begin
            receiveData.CopyFrom(chunks[0].chunkStream,0);
          end else begin
            chunk1.CopyFrom(chunks[0].chunkStream,0);
          end;
          for i:=1 to high(chunks) do begin
            receiveData.Size:=0;
            chunk1.Position:=0;
            chunks[i].chunkStream.Position:=0;
            If Not TPCSafeBox.ConcatSafeBoxStream(chunk1,chunks[i].chunkStream,receiveData,errors) then begin
              TLog.NewLog(ltError,CT_LogSender,errors);
              exit;
            end;
            chunk1.Size := 0;
            chunk1.CopyFrom(receiveData,0);
          end;
        finally
          chunk1.Free;
        end;
      finally
        for i:=0 to high(chunks) do begin
          chunks[i].chunkStream.Free;
        end;
        SetLength(chunks,0);
      end;
      // Now receiveData is the ALL safebox
      PascalCoinNode.DisableNewBlocks;
      try
        PascalCoinSafeBox.StartThreadSafe;
        try
          receiveData.Position:=0;
          If PascalCoinBank.LoadBankFromStream(receiveData,True,errors) then begin
            TLog.NewLog(ltInfo,ClassName,'Received new safebox!');
            If Not IsMyBlockchainValid then begin
              PascalCoinBank.Storage.EraseStorage;
            end;
            PascalCoinBank.Storage.SaveBank;
            Connection.Send_GetBlocks(PascalCoinSafeBox.BlocksCount,100,request_id);
            Result := true;
          end else begin
            Connection.DisconnectInvalidClient(false,'Cannot load from stream! '+errors);
            exit;
          end;
        finally
          PascalCoinSafeBox.EndThreadSave;
        end;
      finally
        PascalCoinNode.EnableNewBlocks;
      end;
    finally
      receiveData.Free;
    end;
  end;

var rid : Cardinal;
  my_op, client_op : TOperationBlock;
  errors : AnsiString;
begin
  // Protection against discovering servers...
  if FIsDiscoveringServers then begin
    TLog.NewLog(ltdebug,CT_LogSender,'Is discovering servers...');
    exit;
  end;
  if (Not Assigned(PascalCoinBank.StorageClass)) then Exit;
  //
  If FIsGettingNewBlockChainFromClient then begin
    TLog.NewLog(ltdebug,CT_LogSender,'Is getting new blockchain from client...');
    exit;
  end else TLog.NewLog(ltdebug,CT_LogSender,'Starting receiving: '+why);
  Try
    FIsGettingNewBlockChainFromClient := true;
    FMaxRemoteOperationBlock := Connection.RemoteOperationBlock;
    if PascalCoinSafeBox.BlocksCount=0 then begin
      TLog.NewLog(ltdebug,CT_LogSender,'I have no blocks');
      If Connection.RemoteOperationBlock.protocol_version>=CT_PROTOCOL_2 then begin
        DownloadSafeBox(False);
      end else begin
        Connection.Send_GetBlocks(0,10,rid);
      end;
      exit;
    end;
    TLog.NewLog(ltdebug,CT_LogSender,'Starting GetNewBlockChainFromClient at client:'+Connection.ClientRemoteAddr+
      ' with OperationBlock:'+TPCOperationsComp.OperationBlockToText(Connection.RemoteOperationBlock)+' (My block: '+TPCOperationsComp.OperationBlockToText(PascalCoinBank.LastOperationBlock)+')');
    // NOTE: FRemoteOperationBlock.block >= PascalCoinBank.BlocksCount
    // First capture same block than me (PascalCoinBank.BlocksCount-1) to check if i'm an orphan block...
    my_op := PascalCoinBank.LastOperationBlock;
    If Not Do_GetOperationBlock(my_op.block,5000,client_op) then begin
      TLog.NewLog(lterror,CT_LogSender,'Cannot receive information about my block ('+inttostr(my_op.block)+')...');
      // Disabled at Build 1.0.6 >  Connection.DisconnectInvalidClient(false,'Cannot receive information about my block ('+inttostr(my_op.block)+')... Invalid client. Disconnecting');
      Exit;
    end;
    // New Build 2.1.7 - Check valid operationblock
    If Not TPCSafeBox.IsValidOperationBlock(client_op,errors) then begin
      Connection.DisconnectInvalidClient(false,'Received invalid operation block '+TPCOperationsComp.OperationBlockToText(client_op)+' errors: '+errors);
      Exit;
    end;

    if (NOT TPCOperationsComp.EqualsOperationBlock(my_op,client_op)) then begin
      TLog.NewLog(ltinfo,CT_LogSender,'My blockchain is not equal... received: '+TPCOperationsComp.OperationBlockToText(client_op)+' My: '+TPCOperationsComp.OperationBlockToText(my_op));
      if Not FindLastSameBlockByOperationsBlock(0,client_op.block,client_op) then begin
        TLog.NewLog(ltinfo,CT_LogSender,'No found base block to start process... Receiving ALL');
        If (Connection.RemoteOperationBlock.protocol_version>=CT_PROTOCOL_2) then begin
          DownloadSafeBox(False);
        end else begin
          GetNewBank(-1);
        end;
      end else begin
        // Move operations to orphan folder... (temporal... waiting for a confirmation)
        if (PascalCoinBank.Storage.FirstBlock<client_op.block) then begin
          TLog.NewLog(ltinfo,CT_LogSender,'Found base new block: '+TPCOperationsComp.OperationBlockToText(client_op));
          GetNewBank(client_op.block+1);
        end else begin
          TLog.NewLog(ltinfo,CT_LogSender,'Found base new block: '+TPCOperationsComp.OperationBlockToText(client_op)+' lower than saved:'+IntToStr(PascalCoinBank.Storage.FirstBlock));
          DownloadSafeBox(False);
        end;
      end;
    end else begin
      TLog.NewLog(ltinfo,CT_LogSender,'My blockchain is ok! Need to download new blocks starting at '+inttostr(my_op.block+1));
      // High to new value:
      Connection.Send_GetBlocks(my_op.block+1,100,rid);
    end;
  Finally
    TLog.NewLog(ltdebug,CT_LogSender,'Finalizing');
    FIsGettingNewBlockChainFromClient := false;
  end;
end;

class function TNetData.HeaderDataToText(const HeaderData: TNetHeaderData): AnsiString;
begin
  Result := CT_NetTransferType[HeaderData.header_type]+' Operation:'+TNetData.OperationToText(HeaderData.operation);
  if HeaderData.is_error then begin
    Result := Result +' ERRCODE:'+Inttostr(HeaderData.error_code)+' ERROR:'+HeaderData.error_text;
  end else begin
    Result := Result +' ReqId:'+Inttostr(HeaderData.request_id)+' BufferSize:'+Inttostr(HeaderData.buffer_data_length);
  end;
end;

procedure TNetData.IncStatistics(incActiveConnections, incClientsConnections,
  incServersConnections,incServersConnectionsWithResponse: Integer; incBytesReceived, incBytesSend: Int64);
begin
  // Multithread prevention
  FNodeServersAddresses.Critical.Acquire;
  Try
    FNetStatistics.ActiveConnections := FNetStatistics.ActiveConnections + incActiveConnections;
    FNetStatistics.ClientsConnections := FNetStatistics.ClientsConnections + incClientsConnections;
    FNetStatistics.ServersConnections := FNetStatistics.ServersConnections + incServersConnections;
    FNetStatistics.ServersConnectionsWithResponse := FNetStatistics.ServersConnectionsWithResponse + incServersConnectionsWithResponse;
    if (incActiveConnections>0) then FNetStatistics.TotalConnections := FNetStatistics.TotalConnections + incActiveConnections;
    if (incClientsConnections>0) then FNetStatistics.TotalClientsConnections := FNetStatistics.TotalClientsConnections + incClientsConnections;
    if (incServersConnections>0) then FNetStatistics.TotalServersConnections := FNetStatistics.TotalServersConnections + incServersConnections;
    FNetStatistics.BytesReceived := FNetStatistics.BytesReceived + incBytesReceived;
    FNetStatistics.BytesSend := FNetStatistics.BytesSend + incBytesSend;
  Finally
    FNodeServersAddresses.Critical.Release;
  End;
  NotifyStatisticsChanged;
  if (incBytesReceived<>0) Or (incBytesSend<>0) then begin
    NotifyNetConnectionUpdated;
  end;
end;

procedure TNetData.SetMaxNodeServersAddressesBuffer(AValue: Integer);
begin
  if FMaxNodeServersAddressesBuffer=AValue then Exit;
  if (AValue<CT_MIN_NODESERVERS_BUFFER) then FMaxNodeServersAddressesBuffer:=CT_MIN_NODESERVERS_BUFFER
  else if (AValue>CT_MAX_NODESERVERS_BUFFER) then FMaxNodeServersAddressesBuffer:=CT_MAX_NODESERVERS_BUFFER
  else FMaxNodeServersAddressesBuffer:=AValue;
end;

procedure TNetData.SetMaxServersConnected(AValue: Integer);
begin
  if FMaxServersConnected=AValue then Exit;
  if AValue<1 then FMaxServersConnected:=1
  else FMaxServersConnected:=AValue;
  if FMaxServersConnected<FMinServersConnected then FMinServersConnected:=FMaxServersConnected;
end;

procedure TNetData.SetMinServersConnected(AValue: Integer);
begin
  if FMinServersConnected=AValue then Exit;
  if AValue<1 then FMinServersConnected:=1
  else FMinServersConnected:=AValue;
  if FMaxServersConnected<FMinServersConnected then FMaxServersConnected:=FMinServersConnected;
end;

function TNetData.NewRequestId: Cardinal;
begin
  Inc(FLastRequestId);
  Result := FLastRequestId;
end;

procedure TNetData.NotifyBlackListUpdated;
begin
  FNotifyOnBlackListUpdated := true;
end;

procedure TNetData.NotifyConnectivityChanged;
begin
  FOnConnectivityChanged.Invoke(Self);
end;

procedure TNetData.NotifyNetConnectionUpdated;
begin
  FNotifyOnNetConnectionsUpdated := true;
end;

procedure TNetData.NotifyNodeServersUpdated;
begin
  FNotifyOnNodeServersUpdated := true;
end;

procedure TNetData.NotifyReceivedHelloMessage;
begin
  FNotifyOnReceivedHelloMessage := true;
end;

procedure TNetData.NotifyStatisticsChanged;
begin
  FNotifyOnStatisticsChanged := true;
end;

class function TNetData.OperationToText(operation: Word): AnsiString;
begin
  case operation of
    CT_NetOp_Hello : Result := 'HELLO';
    CT_NetOp_Error : Result := 'ERROR';
    CT_NetOp_GetBlocks : Result := 'GET BLOCKS';
    CT_NetOp_Message : Result := 'MESSAGE';
    CT_NetOp_GetBlockHeaders : Result := 'GET BLOCK HEADERS';
    CT_NetOp_NewBlock : Result := 'NEW BLOCK';
    CT_NetOp_AddOperations : Result := 'ADD OPERATIONS';
    CT_NetOp_GetSafeBox : Result := 'GET SAFEBOX';
    CT_NetOp_GetPendingOperations : Result := 'GET PENDING OPERATIONS';
    CT_NetOp_GetAccount : Result := 'GET ACCOUNT';
  else Result := 'UNKNOWN OPERATION '+Inttohex(operation,4);
  end;
end;

function TNetData.PendingRequest(Sender: TNetConnection; var requests_data : AnsiString): Integer;
Var P : PNetRequestRegistered;
  i : Integer;
  l : TList;
begin
  requests_data := '';
  l := FRegisteredRequests.LockList;
  Try
    if Assigned(Sender) then begin
      Result := 0;
      for i := l.Count - 1 downto 0 do begin
        if (PNetRequestRegistered(l[i])^.NetClient=Sender) then begin
          requests_data := requests_data+'Op:'+OperationToText(PNetRequestRegistered(l[i])^.Operation)+' Id:'+Inttostr(PNetRequestRegistered(l[i])^.RequestId)+' - ';
          inc(Result);
        end;
      end;
    end else Result := l.Count;
  Finally
    FRegisteredRequests.UnlockList;
  End;
end;

procedure TNetData.RegisterRequest(Sender: TNetConnection; operation: Word; request_id: Cardinal);
Var P : PNetRequestRegistered;
  l : TList;
begin
  l := FRegisteredRequests.LockList;
  Try
    New(P);
    P^.NetClient := Sender;
    P^.Operation := operation;
    P^.RequestId := request_id;
    P^.SendTime := Now;
    l.Add(P);
    TLog.NewLog(ltdebug,Classname,'Registering request to '+Sender.ClientRemoteAddr+' Op:'+OperationToText(operation)+' Id:'+inttostr(request_id)+' Total pending:'+Inttostr(l.Count));
  Finally
    FRegisteredRequests.UnlockList;
  End;
end;

procedure TNetData.SetNetConnectionsActive(const Value: Boolean);
begin
  FNetConnectionsActive := Value;
  NotifyConnectivityChanged;
  if FNetConnectionsActive then DiscoverServers
  else DisconnectClients;
end;

function TNetData.UnRegisterRequest(Sender: TNetConnection; operation: Word; request_id: Cardinal): Boolean;
Var P : PNetRequestRegistered;
  i : Integer;
  l : TList;
begin
  Result := false;
  l := FRegisteredRequests.LockList;
  try
    for i := l.Count - 1 downto 0 do begin
      P := l[i];
      if (P^.NetClient=Sender) And
        ( ((Operation=P^.Operation) And (request_id = P^.RequestId))
          Or
          ((operation=0) And (request_id=0)) ) then begin
        l.Delete(i);
        Dispose(P);
        Result := true;
        if Assigned(Sender.TcpIpClient) then begin
          TLog.NewLog(ltdebug,Classname,'Unregistering request to '+Sender.ClientRemoteAddr+' Op:'+OperationToText(operation)+' Id:'+inttostr(request_id)+' Total pending:'+Inttostr(l.Count));
        end else begin
          TLog.NewLog(ltdebug,Classname,'Unregistering request to (NIL) Op:'+OperationToText(operation)+' Id:'+inttostr(request_id)+' Total pending:'+Inttostr(l.Count));
        end;
      end;
    end;
  finally
    FRegisteredRequests.UnlockList;
  end;
end;

// Skybuck: threaded routines:
procedure TNetData.CheckConnectionsThread( Sender : TObject );
Var l : TList;
  i, nactive,ndeleted,nserverclients : Integer;
  netconn : TNetConnection;
  netserverclientstop : TNetServerClient;
  newstats : TNetStatistics;
  LastCheckTS : TTickCount;
begin
  LastCheckTS := TPlatform.GetTickCount;
  while (Not FThreadCheckConnections.Terminated) do begin
    if ((TPlatform.GetTickCount>(LastCheckTS+1000)) AND (Not FIsDiscoveringServers)) then begin
      nactive := 0;
      ndeleted := 0;
      nserverclients := 0;
      netserverclientstop := Nil;
      LastCheckTS := TPlatform.GetTickCount;
      If (FNetConnections.TryLockList(100,l)) then begin
        try
          newstats := CT_TNetStatistics_NUL;
          for i := l.Count-1 downto 0 do begin
            netconn := TNetConnection(l.Items[i]);
            if (netconn is TNetClient) then begin
              if (netconn.Connected) then begin
                inc(newstats.ServersConnections);
                if (netconn.HasReceivedData) then inc(newstats.ServersConnectionsWithResponse);
              end;
              if (Not TNetClient(netconn).Connected) And (netconn.CreatedTime+EncodeTime(0,0,5,0)<now) then begin
                // Free this!
                TNetClient(netconn).FinalizeConnection;
                inc(ndeleted);
              end else inc(nactive);
            end else if (netconn is TNetServerClient) then begin
              if (netconn.Connected) then begin
                inc(newstats.ClientsConnections);
              end;
              inc(nserverclients);
              if (Not netconn.DoFinalizeConnection) then begin
                // Build 1.0.9 BUG-101 Only disconnect old versions prior to 1.0.9
                if not assigned(netserverclientstop) then begin
                  netserverclientstop := TNetServerClient(netconn);
                end else if (netconn.CreatedTime<netserverclientstop.CreatedTime) then begin
                  netserverclientstop := TNetServerClient(netconn);
                end;
              end;
            end;
          end;
          // Update stats:
          FNetStatistics.ActiveConnections := newstats.ClientsConnections + newstats.ServersConnections;
          FNetStatistics.ClientsConnections := newstats.ClientsConnections;
          FNetStatistics.ServersConnections := newstats.ServersConnections;
          FNetStatistics.ServersConnectionsWithResponse := newstats.ServersConnectionsWithResponse;
          // Must stop clients?
          if (nserverclients>MaxServersConnected) And // This is to ensure there are more serverclients than clients
             ((nserverclients + nactive + ndeleted)>=FMaxConnections) And (Assigned(netserverclientstop)) then begin
            TLog.NewLog(ltinfo,Classname,Format('Sending FinalizeConnection to NodeConnection %s created on %s (working time %s) - NetServerClients:%d Servers_active:%d Servers_deleted:%d',
              [netserverclientstop.Client.ClientRemoteAddr,FormatDateTime('hh:nn:ss',netserverclientstop.CreatedTime),
               FormatDateTime('hh:nn:ss',Now - netserverclientstop.CreatedTime),
               nserverclients,nactive,ndeleted]));
            netserverclientstop.FinalizeConnection;
          end;
        finally
          FNetConnections.UnlockList;
        end;
        if (nactive<=MaxServersConnected) And (Not FThreadCheckConnections.Terminated) then begin
          // Discover
          DiscoverServers;
        end;
      end;
    end;
    sleep(100);
  end;
end;

procedure TNetData.DestroyClientsThread( Sender : TObject );
Var l,l_to_del : TList;
  i : Integer;
begin
  FTerminatedAllConnections := true;
  l_to_del := TList.Create;
  Try
    while not FNetClientsDestroyThread.Terminated do begin
      l_to_del.Clear;
      l := NetConnections.LockList;
      try
        FTerminatedAllConnections := l.Count=0;
        for i := 0 to l.Count-1 do begin
          If (TObject(l[i]) is TNetClient) And (not TNetConnection(l[i]).Connected)
            And (TNetConnection(l[i]).DoFinalizeConnection)
            And (Not TNetConnection(l[i]).IsConnecting) then begin
            l_to_del.Add(l[i]);
          end;
        end;
      finally
        NetConnections.UnlockList;
      end;
      sleep(500); // Delay - Sleep time before destroying (1.5.3)
      if l_to_del.Count>0 then begin
        TLog.NewLog(ltDebug,ClassName,'Destroying NetClients: '+inttostr(l_to_del.Count));
        for i := 0 to l_to_del.Count - 1 do begin
          Try
            FNetClientsDestroyThread.DebugStep := 'Destroying NetClient '+TNetConnection(l_to_del[i]).ClientRemoteAddr;
            TNetConnection(l_to_del[i]).Free;
          Except
            On E:Exception do begin
              TLog.NewLog(ltError,ClassName,'Exception destroying TNetConnection '+IntToHex(PtrInt(l_to_del[i]),8)+': ('+E.ClassName+') '+E.Message );
            end;
          End;
        end;
      end;
      Sleep(100);
    end;
  Finally
    l_to_del.Free;
  end;
end;

procedure TNetData.WaitForTerminatedAllConnections;
begin
  while (Not FTerminatedAllConnections) do begin
    TLog.NewLog(ltdebug,ClassName,'Waiting all connections terminated');
    Sleep(100);
  end;
end;

{ TNetDataNotifyEventsThread }

{ TNetDataNotifyEventsThread ensures that notifications of TNetData object
  will be in main Thread calling a Synchronized method }

procedure TNetData.SynchronizedNotify;
begin
  if FNetDataNotifyEventsThread.Terminated then exit;

  // nil/sender used to be FNetData, probably not thread-safe to pass that anyway ;)
  if FNotifyOnReceivedHelloMessage then begin
    FNotifyOnReceivedHelloMessage := false;
    If Assigned(FOnReceivedHelloMessage) then FOnReceivedHelloMessage(nil);
  end;
  if FNotifyOnStatisticsChanged then begin
    FNotifyOnStatisticsChanged := false;
    If Assigned(FOnStatisticsChanged) then FOnStatisticsChanged(nil);
  end;
  if FNotifyOnNetConnectionsUpdated then begin
    FNotifyOnNetConnectionsUpdated := false;
    If Assigned(FOnNetConnectionsUpdated) then FOnNetConnectionsUpdated(nil);
  end;
  if FNotifyOnNodeServersUpdated then begin
    FNotifyOnNodeServersUpdated := false;
    If Assigned(FOnNodeServersUpdated) then FOnNodeServersUpdated(nil);
  end;
  if FNotifyOnBlackListUpdated then begin
    FNotifyOnBlackListUpdated := false;
    If Assigned(FOnBlackListUpdated) then FOnBlackListUpdated(nil);
  end;
end;

procedure TNetData.NotifyEventsThread( Sender : TObject );
begin
  while (not FNetDataNotifyEventsThread.Terminated) do begin
    if (FNotifyOnReceivedHelloMessage) Or
       (FNotifyOnStatisticsChanged) Or
       (FNotifyOnNetConnectionsUpdated) Or
       (FNotifyOnNodeServersUpdated) Or
       (FNotifyOnBlackListUpdated) then begin
      // Skybuck:
//      TPCCustomThread(Sender).Synchronize(SynchronizedNotify); // also not working... double damn ;) :)
//      FNetDataNotifyEventsThread.Synchronize(SynchronizedNotify); // inaccessible here... damn.
        TThread.Synchronize(FNetDataNotifyEventsThread,SynchronizedNotify); // this should be the solution ! =D
    end;
    Sleep(10);
  end;
end;

initialization
  PascalNetData := Nil;

finalization
  FreeAndNil(PascalNetData);

end.
