unit UPoolMining;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{ Copyright (c) 2016 by Albert Molina

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.

  This unit is a part of Pascal Coin, a P2P crypto currency without need of
  historical operations.

  If you like it, consider a donation using BitCoin:
  16K3HCZRhFUtM8GdWRcfKeaa6KsuyxZaYk

  }

interface

Uses
{$IFnDEF FPC}
  Windows,
{$ELSE}
  {LCLIntf, LCLType, LMessages,}
{$ENDIF}
  UTCPIP, SysUtils, UThread, SyncObjs, Classes, UJSONFunctions, UAES, UNode,
  UCrypto, UAccounts, UConst;

Const
  CT_PoolMining_Method_STATUS = 'status';
  CT_PoolMining_Method_MINER_NOTIFY = 'miner-notify'; // Server message to clients to update miners PoW data
  CT_PoolMining_Method_MINER_SUBMIT = 'miner-submit'; // Client message to server to notify a PoW found

  CT_PoolMining_Method_STRATUM_MINING_AUTHORIZE = 'mining-authorize';
  CT_PoolMining_Method_STRATUM_MINING_SUBSCRIBE = 'mining-subscribe';

Type
  TMinerValuesForWork = Record
     block : Cardinal;
     version : Word;
     part1 : TRawBytes;
     payload_start : TRawBytes;
     part3 : TRawBytes;
     target : Cardinal;
     timestamp : Cardinal;
     target_pow : TRawBytes;
     // Stratum jobid
     jobid : String;
  End;

  TProcessJSONObjectEvent = Procedure (json : TPCJSONObject; method : String) of object;

  { TJSONRPCTcpIpClient }

  TJSONRPCTcpIpClient = Class(TBufferedNetTcpIpClient)
  private
    FLastId : Cardinal;
    FLockProcessBuffer : TCriticalSection;
    FReceivedBuffer : TBytes;
    FLockReceivedBuffer : TCriticalSection;
    FPendingResponseMessages : TPCThreadList;
  protected
  public
    Constructor Create(AOwner : TComponent); override;
    Destructor Destroy; override;
    Procedure SendJSONRPCErrorResponse(const id : Variant; const error : String);
    Procedure SendJSONRPCResponse(result : TPCJSONObject; const id : Variant);
    Procedure SendJSONRPCMethod(const method : String; params : TPCJSONList; const id : Variant);
    Function SendJSONRPCMethodAndWait(const method : String; params : TPCJSONList; MaxWaitMiliseconds : Cardinal; resultObject : TPCJSONObject; processEventOnInvalid : TProcessJSONObjectEvent = Nil) : Boolean;
    Function DoProcessBuffer(SenderThread : TPCThread; MaxWaitMiliseconds : Cardinal; DeleteBufferOnExit : Boolean; var ResponseMethod : String; var jsonObject : TPCJSONObject) : Boolean;
    Function GetNewId : Cardinal;
  End;

  TPoolType = (ptNone,ptIdentify);

  { TPoolMinerClient }

  TPoolMinerClient = Class(TJSONRPCTcpIpClient)
  private
    FMinerValuesForWork: TMinerValuesForWork;
    FOnMinerMustChangeValues: TNotifyEvent;
    FPassword: String;
    FPoolFinalMinerName: String;
    FPoolType: TPoolType;
    FStratum_Target_PoW: TRawBytes;
    FUserName: String;
    procedure SetMinerValuesForWork(const Value: TMinerValuesForWork);
  protected
    Procedure DoOnConnect; Override;
  public
    Constructor Create(AOwner : TComponent); override;
    Property OnMinerMustChangeValues : TNotifyEvent read FOnMinerMustChangeValues write FOnMinerMustChangeValues;
    Property MinerValuesForWork : TMinerValuesForWork read FMinerValuesForWork write SetMinerValuesForWork;
    Procedure SubmitBlockFound(Const MinerValuesToGenerateBlock : TMinerValuesForWork; const Payload: TRawBytes; Timestamp, NOnce: Cardinal);
    Procedure DoProcessJSONObject(json : TPCJSONObject; ResponseMethod : String);
    Property PoolType : TPoolType read FPoolType write FPoolType;
    Property UserName : String read FUserName write FUserName;
    Property Password : String read FPassword write FPassword;
    Property PoolFinalMinerName : String read FPoolFinalMinerName;
    Property Stratum_Target_PoW : TRawBytes read FStratum_Target_PoW;
  End;

  TPoolMiningServer = Class(TNetTcpIpServer)
  private
    FIncomingsCounter : Integer;
    FNodeNotifyEvents : TNodeNotifyEvents;
    FMinerAccountKey: TAccountKey;
    FMinerPayload: TRawBytes;
    FClientsWins: Integer;
    FClientsCount: Integer;
    FOnMiningServerNewBlockFound: TNotifyEvent;
    Procedure DoProcessJSON(json : TPCJSONObject; ResponseMethod : String; Client : TJSONRPCTcpIpClient);
    Procedure OnNodeNewBlock(Sender : TObject);
    Procedure OnNodeOperationsChanged(Sender : TObject);
    Procedure Send_mine_values_to_all;
    Procedure FillMineValue(mine_values : TPCJSONObject; Client : TJSONRPCTcpIpClient);
    Function MinerSubmit(Client : TJSONRPCTcpIpClient; params : TPCJSONObject; const id : Variant) : Boolean;
    procedure SetMinerAccountKey(const Value: TAccountKey);
    procedure SetMinerPayload(const Value: TRawBytes);
  protected
    Procedure OnNewIncommingConnection(Sender : TObject; Client : TNetTcpIpClient); override;
    procedure SetActive(const Value: Boolean); override;
  public
    Constructor Create; override;
    Destructor Destroy; override;
    Property MinerAccountKey : TAccountKey read FMinerAccountKey write SetMinerAccountKey;
    Property MinerPayload : TRawBytes read FMinerPayload write SetMinerPayload;
    Procedure UpdateAccountAndPayload(AMinerAccountKey : TAccountKey; AMinerPayload : TRawBytes);
    Property ClientsCount : Integer read FClientsCount;
    Property ClientsWins : Integer read FClientsWins;
    Property OnMiningServerNewBlockFound : TNotifyEvent read FOnMiningServerNewBlockFound write FOnMiningServerNewBlockFound;
  End;

Function TBytesToString(Const bytes : TBytes):AnsiString;

Const
  CT_TMinerValuesForWork_NULL : TMinerValuesForWork = (block:0;version:0;part1:'';payload_start:'';part3:'';target:0;timestamp:0;target_pow:'';jobid:'');

implementation

Uses ULog, Variants, UTime, UBlockChain;

Type TPendingResponseMessage = Record
       sendDateTime : TDateTime;
       maxDateTime : TDateTime;
       id : Integer;
       method : String;
     end;
  PPendingResponseMessage = ^TPendingResponseMessage;

Function TBytesToString(Const bytes : TBytes):AnsiString;
Var i : Integer;
Begin
  Result := '';
  for i := 0 to high(bytes) do begin
    if (bytes[i]<32) then Result := Result+'#'+IntToHex(bytes[i],2)
    else if bytes[i]=ord('#') then Result := Result+'##'
    else Result := Result + ansichar(bytes[i]);
  end;
End;

{ TJSONRPCTcpIpClient }

constructor TJSONRPCTcpIpClient.Create(AOwner: TComponent);
begin
  inherited;
  FLastId := 1;
  SetLength(FReceivedBuffer,0);
  FLockProcessBuffer := TCriticalSection.Create;
  FLockReceivedBuffer := TCriticalSection.Create;
  FPendingResponseMessages := TPCThreadList.Create;
end;

destructor TJSONRPCTcpIpClient.Destroy;
var P : PPendingResponseMessage;
  l : TList;
  i : Integer;
begin
  l := FPendingResponseMessages.LockList;
  try
    for i:=0 to l.count-1 do begin
      P:=l[i];
      Dispose(P);
    end;
    l.clear;
  finally
    FPendingResponseMessages.UnlockList;
  end;
  FreeAndNil(FLockReceivedBuffer);
  FreeAndNil(FLockProcessBuffer);
  SetLength(FReceivedBuffer,0);
  FreeAndNil(FPendingResponseMessages);
  inherited;
end;

function TJSONRPCTcpIpClient.DoProcessBuffer(SenderThread : TPCThread; MaxWaitMiliseconds : Cardinal; DeleteBufferOnExit : Boolean; var ResponseMethod : String; var jsonObject : TPCJSONObject) : Boolean;
var last_bytes_read : Integer;
  jsonData : TPCJSONData;
  tc : Cardinal;
  ms : TMemoryStream;
  i,lasti : Integer;
  continue : Boolean;
  procedure FlushBufferPendingMessages(doSearchId : Boolean; idValue : Integer);
  var l : TList;
    i : Integer;
    P : PPendingResponseMessage;
  Begin
    l := FPendingResponseMessages.LockList;
    Try
      for i := l.count-1 downto 0 do begin
        P := l[i];
        if (doSearchId) And (idValue=P^.id) then begin
          ResponseMethod:=P^.method;
          Dispose(P);
          l.Delete(i);
        end else if (P^.maxDateTime<now) then begin
          TLog.NewLog(lterror,Classname,'Deleting a Pending response message id:'+inttostr(P^.id)+' method:'+P^.method);
          Dispose(P);
          l.Delete(i);
        end;
      end;
    finally
      FPendingResponseMessages.UnlockList;
    end;
  end;
var PartialBuffer : TBytes;
  Function ProcessPartialBuffer : Boolean;
  Var i,istart : Integer;
    aux : TBytes;
  begin
    result := false;
    i := 0; istart :=0;
    while (i<=high(FReceivedBuffer)) do begin
      if FReceivedBuffer[i]<32 then begin
        if i=istart then inc(istart)
        else break;
      end else begin
      end;
      inc(i);
    end;
    if (i>0) And (i>istart) And (i<=High(FReceivedBuffer)) then begin
      SetLength(PartialBuffer,i-istart);
      move(FReceivedBuffer[istart],PartialBuffer[0],i-istart);
      // Inc i until valid char
      while (i<=High(FReceivedBuffer)) And (FReceivedBuffer[i]<32) do inc(i);
      // i is the first valid pos for next buffer
      if i<=High(FReceivedBuffer) then begin
        setlength(aux,length(FReceivedBuffer)-i);
        move(FReceivedBuffer[i],aux[0],length(aux));
        SetLength(FReceivedBuffer,length(aux));
        move(aux[0],FReceivedBuffer[0],length(aux));
      end else begin
        // empty next buffer
        SetLength(FReceivedBuffer,0);
      end;
      Result := true;
    end;
  end;
var islocked : Boolean;
begin
  Result := false;
  ResponseMethod := '';
  tc := GetTickCount;
  Repeat
    islocked := FLockProcessBuffer.TryEnter;
  until (islocked) Or ((GetTickCount>(tc+MaxWaitMiliseconds)) And (MaxWaitMiliseconds<>0));
  If Not islocked then exit;
  try
    if Assigned(SenderThread) then continue := Not SenderThread.Terminated
    else continue := true;
    while (Connected) And ((GetTickCount<=(tc+MaxWaitMiliseconds)) Or (MaxWaitMiliseconds=0)) And (continue) do begin
      last_bytes_read := 0;
      ms := ReadBufferLock;
      try
        if (ms.Size)>0 then begin
          lasti := length(FReceivedBuffer);
          setLength(FReceivedBuffer,length(FReceivedBuffer)+ms.Size);
          CopyMemory(@FReceivedBuffer[lasti],ms.Memory,ms.Size);
          last_bytes_read := ms.Size;
          ms.Size := 0;
        end;
      finally
        ReadBufferUnlock;
      end;
      If ProcessPartialBuffer then begin
        // Decode
        jsonData := TPCJSONData.ParseJSONValue(PartialBuffer);
        if Assigned(jsonData) then begin
          if jsonData is TPCJSONObject then begin
            jsonObject.Assign(jsonData);
            If (Not jsonObject.IsNull('id')) And (jsonObject.IndexOfName('method')<0) then begin
              // Is a Response!
              FlushBufferPendingMessages(true,jsonObject.AsInteger('id',0));
            end;
            Result := true;
            exit;
          end else begin
            TLog.NewLog(lterror,ClassName,'Invalid JSON class: '+jsonData.ClassName+' json: '+TBytesToString(PartialBuffer));
            jsonData.Free;
          End;
        end else begin
          TLog.NewLog(lterror,ClassName,Format('Read %d bytes but no valid JSON inside: %s',[last_bytes_read,TBytesToString(PartialBuffer)]));
        end;
      end;
      sleep(1);
      if Assigned(SenderThread) then continue := Not SenderThread.Terminated
      else continue := true;
    end;
    if (length(FReceivedBuffer)>0) And (DeleteBufferOnExit) then begin
      TLog.NewLog(lterror,ClassName,AnsiString( Format('Deleting %d bytes from buffer after waiting %d milis: %s',[length(FReceivedBuffer),MaxWaitMiliseconds,TBytesToString(FReceivedBuffer)])));
      SetLength(FReceivedBuffer,0);
    end;
  finally
    FlushBufferPendingMessages(false,0);
    FLockProcessBuffer.Release;
  end;
end;

function TJSONRPCTcpIpClient.GetNewId: Cardinal;
begin
  FLockReceivedBuffer.Acquire;
  try
    inc(FLastId);
    Result := FLastId;
  finally
    FLockReceivedBuffer.Release;
  end;
end;

procedure TJSONRPCTcpIpClient.SendJSONRPCErrorResponse(const id: Variant; const error: String);
Var response : TPCJSONObject;
  stream : TMemoryStream;
  b : Byte;
begin
  TLog.NewLog(lterror,ClassName,'Sending Error JSON RPC id ('+VarToStr(id)+') : '+error);
  response := TPCJSONObject.Create;
  Try
    response.GetAsVariant('result').Value := Null;
    response.GetAsVariant('error').Value := error;
    response.GetAsVariant('id').Value := id;
    stream := TMemoryStream.Create;
    try
      response.SaveToStream(stream);
      b := 13;
      stream.Write(b,1);
      b := 10;
      stream.Write(b,1);
      b := 0;
      stream.Write(b,1);
      stream.Position := 0;
      WriteBufferToSend(stream);
    finally
      stream.Free;
    end;
  Finally
    response.Free;
  End;
end;

procedure TJSONRPCTcpIpClient.SendJSONRPCMethod(const method: String; params: TPCJSONList; const id: Variant);
Var json : TPCJSONObject;
  stream : TMemoryStream;
  b : Byte;
  P : PPendingResponseMessage;
  l : TList;
begin
  json := TPCJSONObject.Create;
  Try
    json.GetAsVariant('id').Value := id;
    json.GetAsVariant('method').Value := method;
    if Assigned(params) then begin
      If params is TPCJSONObject then begin
        json.GetAsArray('params').GetAsObject(0).Assign(params);
      end else if params is TPCJSONArray then begin
        json.GetAsArray('params').Assign(params);
      end;
    end;
    if (Not VarIsNull(id)) then begin
      new(P);
      P^.id:=id;
      P^.sendDateTime:=Now;
      P^.maxDateTime:=Now + encodetime(0,0,30,0);
      P^.method:=method;
      FPendingResponseMessages.Add(P);
    end;
    TLog.NewLog(ltdebug,Classname,'Sending JSON-RPC: '+json.ToJSON(false));
    stream := TMemoryStream.Create;
    try
      json.SaveToStream(stream);
      b := 13;
      stream.Write(b,1);
      b := 10;
      stream.Write(b,1);
      stream.Position := 0;
      WriteBufferToSend(stream);
    finally
      stream.Free;
    end;
  Finally
    json.Free;
  End;
end;

function TJSONRPCTcpIpClient.SendJSONRPCMethodAndWait(const method: String; params: TPCJSONList; MaxWaitMiliseconds: Cardinal; resultObject : TPCJSONObject; processEventOnInvalid : TProcessJSONObjectEvent = Nil) : Boolean;
Var nId : Cardinal;
  tc,maxw : Cardinal;
  json : TPCJSONObject;
  rm : String;
begin
  Result := false;
  FLockProcessBuffer.Acquire;
  try
    nId := GetNewId;
    SendJSONRPCMethod(method,params,nId);
    tc := GetTickCount;
    json := TPCJSONObject.Create;
    Try
      repeat
        maxw := MaxWaitMiliseconds - (GetTickCount - tc);
        if maxw<1 then maxw := 1
        else if maxw>10000 then maxw := 10000;
        If DoProcessBuffer(nil,maxw,true,rm,json) then begin
          If json.AsCardinal('id',0)=nId then begin
            resultObject.Assign(json);
            Result := true;
          end else begin
            TLog.NewLog(ltdebug,classname,'Received a unexpected JSON while waiting for response Id:'+inttostr(nId)+' Received:'+json.ToJSON(false));
            If Assigned(processEventOnInvalid) then begin
              TLog.NewLog(ltdebug,classname,'Sending to process unexpected JSON:'+json.ToJSON(false));
              processEventOnInvalid(json,rm);
            end else TLog.NewLog(ltdebug,Classname,'Lost JSON message! '+json.ToJSON(false));
          end;
        end;
      until (Result) Or (GetTickCount > (tc+MaxWaitMiliseconds));
    finally
      json.free;
    end;
    if (Not Result) then begin
      TLog.NewLog(ltdebug,classname,'Not received a JSON response Id:'+inttostr(nId)+' for method:'+method);
    end;
  finally
    FLockProcessBuffer.Release;
  end;
end;

procedure TJSONRPCTcpIpClient.SendJSONRPCResponse(result: TPCJSONObject; const id: Variant);
Var response : TPCJSONObject;
  stream : TMemoryStream;
  b : Byte;
begin
  response := TPCJSONObject.Create;
  Try
    If Assigned(Result) then response.GetAsObject('result').Assign(result)
    else response.GetAsVariant('result').Value:=null;
    response.GetAsVariant('error').Value := Null;
    response.GetAsVariant('id').Value := id;
    stream := TMemoryStream.Create;
    try
      response.SaveToStream(stream);
      b := 13;
      stream.Write(b,1);
      b := 10;
      stream.Write(b,1);
      stream.Position := 0;
      WriteBufferToSend(stream);
    finally
      stream.Free;
    end;
  Finally
    response.Free;
  End;
end;

{ TPoolMiningServer }

constructor TPoolMiningServer.Create;
begin
  inherited;
  FOnMiningServerNewBlockFound := Nil;
  FIncomingsCounter := 0;
  FClientsWins := 0;
  FClientsCount := 0;
  MaxConnections:=1000;
  NetTcpIpClientClass := TJSONRPCTcpIpClient;
  FNodeNotifyEvents := TNodeNotifyEvents.Create(Nil);
  FNodeNotifyEvents.OnBlocksChanged := OnNodeNewBlock;
  FNodeNotifyEvents.OnOperationsChanged := OnNodeOperationsChanged;
  FNodeNotifyEvents.Node := TNode.Node;
  FMinerAccountKey := CT_TECDSA_Public_Nul;
end;

destructor TPoolMiningServer.Destroy;
begin
  FNodeNotifyEvents.Node := Nil;
  FNodeNotifyEvents.OnBlocksChanged := Nil;
  FNodeNotifyEvents.OnOperationsChanged := Nil;
  FreeAndNil(FNodeNotifyEvents);
  inherited;
end;

procedure TPoolMiningServer.DoProcessJSON(json: TPCJSONObject; ResponseMethod : String; Client : TJSONRPCTcpIpClient);
Var method : String;
    params : TPCJSONArray;
    id_value : Variant;
    i : Integer;
  response_result : TPCJSONObject;
begin
  If ResponseMethod<>'' then begin
    method := ResponseMethod;
    params := json.GetAsArray('result');
  end else begin
    method := json.AsString('method','');
    params := json.GetAsArray('params');
  end;
  i := json.IndexOfName('id');
  if i<0 then begin
    id_value := Null;
  end else begin
    id_value := json.GetAsVariant('id').Value;
  end;
  if method=CT_PoolMining_Method_STATUS then begin
    response_result := TPCJSONObject.Create;
    Try
      response_result.GetAsVariant('block').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.block;
      response_result.GetAsVariant('account_key').Value := TCrypto.ToHexaString( TAccountComp.AccountKey2RawString(FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.account_key) );
      response_result.GetAsVariant('reward').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.reward;
      response_result.GetAsVariant('fee').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.fee;
      response_result.GetAsVariant('p_version').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.protocol_version;
      response_result.GetAsVariant('p_available').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.protocol_available;
      response_result.GetAsVariant('timestamp').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.timestamp;
      response_result.GetAsVariant('target').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.compact_target;
      response_result.GetAsVariant('nonce').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.nonce;
      response_result.GetAsVariant('payload').Value := TCrypto.ToHexaString( FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.block_payload );
      response_result.GetAsVariant('initial_sbh').Value := TCrypto.ToHexaString( FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.initial_safe_box_hash );
      response_result.GetAsVariant('operations_hash').Value := TCrypto.ToHexaString( FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.operations_hash );
      response_result.GetAsVariant('pow').Value := TCrypto.ToHexaString( FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.proof_of_work );
      Client.SendJSONRPCResponse(response_result,id_value);
    Finally
      response_result.Free;
    End;
  end else if method=CT_PoolMining_Method_MINER_NOTIFY then begin
    response_result := TPCJSONObject.Create;
    Try
      FillMineValue(response_result,Client);
      Client.SendJSONRPCResponse(response_result,id_value);
    Finally
      response_result.Free;
    End;
  end else if method=CT_PoolMining_Method_MINER_SUBMIT then begin
    // Try to submit a PoW
    if params.Count=1 then MinerSubmit(Client,params.GetAsObject(0),id_value)
    else TLog.NewLog(lterror,ClassName,'Invalid params array of method '+method);
  end else begin
    // Invalid command
    if (not VarIsNull(id_value)) then begin
      Client.SendJSONRPCErrorResponse(id_value,'method not found: '+method);
    end;
  end;
end;

procedure TPoolMiningServer.FillMineValue(mine_values: TPCJSONObject; Client : TJSONRPCTcpIpClient);
Var Op : TPCOperationsComp;
  ts : Cardinal;
begin
  mine_values.GetAsVariant('block').Value := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.block+1;
  mine_values.GetAsVariant('version').Value := FNodeNotifyEvents.Node.Operations.OperationBlock.protocol_version;
  Op := TPCOperationsComp.Create(Nil);
  try
    Op.CopyFrom(FNodeNotifyEvents.Node.Operations);
    Op.AccountKey := FMinerAccountKey;
    Op.BlockPayload := FMinerPayload;
    mine_values.GetAsVariant('part1').Value := TCrypto.ToHexaString( Op.PoW_Digest_Part1 );
    mine_values.GetAsVariant('payload_start').Value := TCrypto.ToHexaString( Op.OperationBlock.block_payload );
    mine_values.GetAsVariant('part3').Value := TCrypto.ToHexaString( Op.PoW_Digest_Part3 );
    mine_values.GetAsVariant('target').Value := Op.OperationBlock.compact_target;
    mine_values.GetAsVariant('target_pow').Value := TCrypto.ToHexaString(FNodeNotifyEvents.Node.Bank.GetActualTargetHash);
  finally
    Op.Free;
  end;
  // Build 1.4.3 Prevent past time mining
  ts := UnivDateTimeToUnix(DateTime2UnivDateTime(now));
  if (ts<FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.timestamp) then begin
    ts := FNodeNotifyEvents.Node.Bank.LastBlockFound.OperationBlock.timestamp;
  end;
  mine_values.GetAsVariant('timestamp').Value := ts;
end;

function TPoolMiningServer.MinerSubmit(Client: TJSONRPCTcpIpClient; params: TPCJSONObject; const id : Variant): Boolean;
Var s : String;
  nbOperations : TPCOperationsComp;
  errors : AnsiString;
  nba : TBlockAccount;
  payload : TRawBytes;
  json : TPCJSONObject;
  p1,p2,p3 : TRawBytes;
begin
  { Miner params must submit:
    - "payload" as an Hexadecimal
    - "timestamp" as an unsigned integer 32 bits
    - "nonce" as an unsigned integer 32 bits
    If payload length is < Node payload then error
    If Node payload is not included in first bytes of payload then error
    If timestamp is not valid then error
    If calculated PoW does not match valid PoW then error
    If all ok... congrats!!! }
  Result := false;
  nbOperations := TPCOperationsComp.Create(Nil);
  try
    nbOperations.bank := FNodeNotifyEvents.Node.Bank;
    nbOperations.CopyFrom(FNodeNotifyEvents.Node.Operations);
    nbOperations.AccountKey := MinerAccountKey;
    s := params.AsString('payload','');
    payload := TCrypto.HexaToRaw(AnsiString(s));
    if FMinerPayload<>'' then begin
      if (copy(payload,1,length(FMinerPayload))<>FMinerPayload) then begin
        Client.SendJSONRPCErrorResponse(id,'Invalid payload ('+payload+'). Need start with: '+FMinerPayload);
        exit;
      end;
    end;
    nbOperations.BlockPayload := payload;
    nbOperations.timestamp := params.AsCardinal('timestamp',0);
    nbOperations.nonce := params.AsCardinal('nonce',0);
    p1 := nbOperations.PoW_Digest_Part1;
    p2 := nbOperations.PoW_Digest_Part2_Payload;
    p3 := nbOperations.PoW_Digest_Part3;
    If FNodeNotifyEvents.Node.AddNewBlockChain(nil,nbOperations,nba,errors) then begin
      // CONGRATS !!!
      json := TPCJSONObject.Create;
      try
        json.GetAsVariant('block').Value := FNodeNotifyEvents.Node.Bank.LastOperationBlock.block;
        json.GetAsVariant('pow').Value := TCrypto.ToHexaString( FNodeNotifyEvents.Node.Bank.LastOperationBlock.proof_of_work );
        json.GetAsVariant('payload').Value := nbOperations.BlockPayload;
        json.GetAsVariant('timestamp').Value := nbOperations.timestamp;
        json.GetAsVariant('nonce').Value := nbOperations.nonce;
        inc(FClientsWins);
        Client.SendJSONRPCResponse(json,id);
      finally
        json.Free;
      end;
      if Assigned(FOnMiningServerNewBlockFound) then FOnMiningServerNewBlockFound(Self);
    end else begin
      Client.SendJSONRPCErrorResponse(id,'Error: '+errors+' payload:'+nbOperations.BlockPayload+' timestamp:'+InttoStr(nbOperations.timestamp)+' nonce:'+IntToStr(nbOperations.nonce));
    end;
  finally
    nbOperations.Free;
  end;
end;

procedure TPoolMiningServer.OnNewIncommingConnection(Sender: TObject; Client: TNetTcpIpClient);
var bClient : TJSONRPCTcpIpClient;
  init_json : TPCJSONObject;
  jsonobj : TPCJSONObject;
  doDelete : Boolean;
  rmethod : String;
begin
  inherited;
  inc(FClientsCount);
  Try
    TLog.NewLog(ltinfo,ClassName,'New Mining Pool Connection: '+Client.ClientRemoteAddr);
    bClient := TJSONRPCTcpIpClient(Client);
    inc(FIncomingsCounter);
    init_json := TPCJSONObject.Create;
    Try
      FillMineValue(init_json,bClient);
      bClient.SendJSONRPCMethod(CT_PoolMining_Method_MINER_NOTIFY,init_json,null);
    Finally
      init_json.Free;
    End;
    while (Active) And (Client.Connected) do begin
      doDelete := bClient.LastReadTC+1000<GetTickCount;  // TODO: Protect GetTickCount overflow
      jsonobj := TPCJSONObject.Create;
      try
        if bClient.DoProcessBuffer(nil,1000,doDelete,rmethod,jsonobj) then begin
          DoProcessJSON(jsonobj,rmethod,bClient);
        end;
      finally
        jsonobj.free;
      end;
      sleep(10);
    end;
  Finally
    Dec(FClientsCount);
    TLog.NewLog(ltinfo,ClassName,'Finalizing Mining Pool Connection: '+Client.ClientRemoteAddr);
  End;
end;

procedure TPoolMiningServer.OnNodeNewBlock(Sender: TObject);
begin
  // Send mine values to all clients
  Send_mine_values_to_all;
end;

procedure TPoolMiningServer.OnNodeOperationsChanged(Sender: TObject);
begin
  // Send mine values to all clients
  Send_mine_values_to_all;
end;

procedure TPoolMiningServer.Send_mine_values_to_all;
var params : TPCJSONObject;
  i : Integer;
  l : TList;
begin
  params := TPCJSONObject.Create;
  Try
    l := NetTcpIpClientsLock;
    Try
      for i := 0 to l.Count - 1 do begin
        if Not Active then exit;
        FillMineValue(params,TJSONRPCTcpIpClient(l[i]));
        TJSONRPCTcpIpClient(l[i]).SendJSONRPCMethod(CT_PoolMining_Method_MINER_NOTIFY,params,Null);
      end;
    Finally
      NetTcpIpClientsUnlock;
    End;
  Finally
    params.Free;
  End;
end;

procedure TPoolMiningServer.SetActive(const Value: Boolean);
begin
  inherited;
  if (Not Value) then begin
    WaitUntilNetTcpIpClientsFinalized;
  end;
end;


procedure TPoolMiningServer.SetMinerAccountKey(const Value: TAccountKey);
begin
  FMinerAccountKey := Value;
  TLog.NewLog(ltdebug,ClassName,'Assigning Miner account key to: '+TCrypto.ToHexaString(TAccountComp.AccountKey2RawString(Value)));
  Send_mine_values_to_all;
end;

procedure TPoolMiningServer.SetMinerPayload(const Value: TRawBytes);
begin
  FMinerPayload := Value;
  TLog.NewLog(ltdebug,ClassName,'Assigning Miner new Payload: '+TCrypto.ToHexaString(Value));
  Send_mine_values_to_all;
end;

procedure TPoolMiningServer.UpdateAccountAndPayload(
  AMinerAccountKey: TAccountKey; AMinerPayload: TRawBytes);
begin
  FMinerAccountKey := AMinerAccountKey;
  TLog.NewLog(ltdebug,ClassName,'Assigning Miner account key to: '+TCrypto.ToHexaString(TAccountComp.AccountKey2RawString(AMinerAccountKey)));
  FMinerPayload := AMinerPayload;
  TLog.NewLog(ltdebug,ClassName,'Assigning Miner new Payload: '+TCrypto.ToHexaString(AMinerPayload));
  Send_mine_values_to_all;
end;

{ TPoolMinerClient }

constructor TPoolMinerClient.Create(AOwner: TComponent);
begin
  FMinerValuesForWork := CT_TMinerValuesForWork_NULL;
  FPoolType:=ptNone;
  FUserName:='';
  FPassword:='';
  FPoolFinalMinerName:='';
  FStratum_Target_PoW:='';
  inherited;
end;

procedure TPoolMinerClient.DoOnConnect;
Var params : TPCJSONArray;
  resultObject : TPCJSONObject;
  s : String;
  raws : TRawBytes;
  i : Integer;
begin
  inherited DoOnConnect;
  If FPoolType=ptIdentify then begin
    // Pool initialization
    params := TPCJSONArray.Create;
    resultObject := TPCJSONObject.Create;
    try
      params.GetAsVariant(0).Value:=UserName;
      params.GetAsVariant(1).Value:=Password;
      If SendJSONRPCMethodAndWait(CT_PoolMining_Method_STRATUM_MINING_AUTHORIZE,params,1000,resultObject,nil) then begin
        TLog.NewLog(ltInfo,Classname,CT_PoolMining_Method_STRATUM_MINING_AUTHORIZE+' response: '+resultObject.ToJSON(false));
        // Now subscribe
        params.Clear;
        resultObject.Clear;
        If SendJSONRPCMethodAndWait(CT_PoolMining_Method_STRATUM_MINING_SUBSCRIBE,params,1000,resultObject,nil) then begin
          //
          TLog.NewLog(ltInfo,Classname,CT_PoolMining_Method_STRATUM_MINING_SUBSCRIBE+' response: '+resultObject.ToJSON(false));
          // Decode response
          If (resultObject.IsNull('error')) then begin
            s := resultObject.GetAsArray('result').GetAsArray(0).GetAsArray(0).GetAsVariant(0).AsString('');
            if (s<>'mining.nonce') then Raise Exception.Create('Not a mining.nonce');
            s := resultObject.GetAsArray('result').GetAsVariant(1).AsString('');
            raws := TCrypto.HexaToRaw(s);
            If (length(s)>0) And (length(raws)=0) then begin
              TLog.NewLog(lterror,ClassName,'Invalid value to assign as a Miner name. Not hexadecimal '+s);
              FPoolFinalMinerName:='';
            end else begin
              FPoolFinalMinerName := raws;
              for i:=1 to length(raws) do begin
                if Not (raws[i] in [#32..#254]) then begin
                  TLog.NewLog(ltError,ClassName,'Invalid proposed miner name. Value at pos '+inttostr(i)+' is not #24..#254: '+IntToStr(integer(raws[i])));
                  FPoolFinalMinerName:='';
                  break;
                end;
              end;
            end;
            TLog.NewLog(ltInfo,Classname,'Final miner name: "'+FPoolFinalMinerName+'" (Length '+IntToStr(length(FPoolFinalMinerName)));
          end;
        end else raise Exception.Create('Not response to "'+CT_PoolMining_Method_STRATUM_MINING_SUBSCRIBE+'" method for user "'+UserName+'"');
      end else raise Exception.Create('Not response to "'+CT_PoolMining_Method_STRATUM_MINING_AUTHORIZE+'" method for user "'+UserName+'"');
    finally
      resultObject.free;
      params.free;
    end;
  end;
end;

procedure TPoolMinerClient.DoProcessJSONObject(json: TPCJSONObject; ResponseMethod : String);
Var method : String;
    id_value : Variant;
    i : Integer;
  params_as_object,pobject : TPCJSONObject;
  params_as_array : TPCJSONArray;
  params : TPCJSONData;
  mvfw : TMinerValuesForWork;
  prev_pow,proposed_pow : TRawBytes;
begin
  TLog.NewLog(ltdebug,ClassName,'Received JSON: '+json.ToJSON(false));
  params := Nil;
  params_as_object := Nil;
  params_as_array := Nil;
  if (ResponseMethod<>'') then begin
    method := ResponseMethod;
    i := json.IndexOfName('result');
    if (i>=0) then begin
      params := json.Items[i];
    end;
    //params_object := json.GetAsObject('result');
    TLog.NewLog(ltinfo,classname,'Received response method:'+ResponseMethod+' JSON:'+json.ToJSON(false));
  end else begin
    method := json.AsString('method','');
    i := json.IndexOfName('params');
    if (i>=0) then begin
      params := json.Items[i];
    end;
  end;
  If Assigned(params) then begin
    if (params is TPCJSONNameValue) then begin
      if (TPCJSONNameValue(params).Value is TPCJSONObject) then params_as_object := TPCJSONObject(TPCJSONNameValue(params).Value)
      else if (TPCJSONNameValue(params).Value is TPCJSONArray) then params_as_array := TPCJSONArray(TPCJSONNameValue(params).Value);
    end;
  end;
  i := json.IndexOfName('id');
  if i<0 then begin
    id_value := Null;
  end else begin
    id_value := json.GetAsVariant('id').Value;
  end;
  if method=CT_PoolMining_Method_MINER_NOTIFY then begin
    If assigned(params_as_array) then pobject := params_as_array.GetAsObject(0)
    else pobject := Nil;
    if assigned(pobject) then begin
      mvfw := CT_TMinerValuesForWork_NULL;
      mvfw.block := pobject.AsInteger('block',0);
      mvfw.version := pobject.AsInteger('version',0);
      mvfw.part1 := TCrypto.HexaToRaw(pobject.AsString('part1',''));
      mvfw.payload_start := TCrypto.HexaToRaw(pobject.AsString('payload_start',''));
      mvfw.part3 := TCrypto.HexaToRaw(pobject.AsString('part3',''));
      mvfw.target := pobject.AsInteger('target',0);
      mvfw.timestamp := pobject.AsInteger('timestamp',0);
      mvfw.part1 := TCrypto.HexaToRaw(pobject.AsString('part1',''));
      mvfw.target_pow := TCrypto.HexaToRaw(pobject.AsString('target_pow',''));
      If FPoolType=ptIdentify then begin
        mvfw.jobid:=pobject.AsString('jobid','');
      end;
      if (Not VarIsNull(id_value)) And (ResponseMethod='') then begin
        SendJSONRPCResponse(pobject,id_value);
      end;
      MinerValuesForWork := mvfw;
    end else TLog.NewLog(ltError,ClassName,'method '+method+' without JSON object '+params.ToJSON(false));
  end;
end;

procedure TPoolMinerClient.SetMinerValuesForWork(const Value: TMinerValuesForWork);
Var _t : Cardinal;
  _t_pow : TRawBytes;
begin
  FMinerValuesForWork := Value;
  If FStratum_Target_PoW<>'' then begin
    FMinerValuesForWork.target:=TPCBank.TargetToCompact(FStratum_Target_PoW);
    FMinerValuesForWork.target_pow:=TPCBank.TargetFromCompact(FMinerValuesForWork.target);
  end else begin
    // Check that target and target_pow are equal!
    _t_pow := TPCBank.TargetFromCompact(FMinerValuesForWork.target);
    if (length(FMinerValuesForWork.target_pow)=32) then begin
      _t := TPCBank.TargetToCompact(FMinerValuesForWork.target_pow);
      if (FMinerValuesForWork.target<CT_MinCompactTarget) then begin
        // target has no valid value... assigning compact_target!
        FMinerValuesForWork.target:=TPCBank.TargetToCompact(_t_pow);
      end else if (_t_pow<>FMinerValuesForWork.target_pow) Or (_t<>FMinerValuesForWork.target) then begin
        TLog.NewLog(ltError,Classname,'Received bad values for target and target_pow!');
        If (FMinerValuesForWork.target<CT_MinCompactTarget) then begin
          FMinerValuesForWork.target_pow:=TPCBank.TargetFromCompact(FMinerValuesForWork.target);
        end else begin
          FMinerValuesForWork.target:=TPCBank.TargetToCompact(_t_pow);
        end;
      end;
    end else begin
      if (FMinerValuesForWork.target<CT_MinCompactTarget) then begin
        // target_pow has no value... assigning target!
        FMinerValuesForWork.target_pow:=TPCBank.TargetFromCompact(FMinerValuesForWork.target);
      end else begin
        // Invalid target and compact_target
        FMinerValuesForWork.target := CT_TMinerValuesForWork_NULL.target;
        FMinerValuesForWork.target_pow := CT_TMinerValuesForWork_NULL.target_pow;
      end;
    end;
  end;
  If (FPoolType=ptIdentify) And (FPoolFinalMinerName<>'') then FMinerValuesForWork.payload_start:=FPoolFinalMinerName;
  if Assigned(FOnMinerMustChangeValues) then FOnMinerMustChangeValues(Self);
end;

procedure TPoolMinerClient.SubmitBlockFound(Const MinerValuesToGenerateBlock : TMinerValuesForWork; const Payload: TRawBytes; Timestamp, NOnce: Cardinal);
Var json, resultJSON : TPCJSONObject;
  nOnceAsSignedInt : Int32;
begin
  json := TPCJSONObject.Create;
  Try
    nOnceAsSignedInt := NOnce;
    If FPoolType=ptIdentify then begin
      json.GetAsVariant('jobid').Value := MinerValuesToGenerateBlock.jobid;
    end;
    json.GetAsVariant('payload').Value := TCrypto.ToHexaString(Payload);
    json.GetAsVariant('timestamp').Value := Timestamp;
    json.GetAsVariant('nonce').Value := nOnceAsSignedInt;
    resultJSON := TPCJSONObject.Create;
    try
      SendJSONRPCMethod(CT_PoolMining_Method_MINER_SUBMIT,json,GetNewId);
    Finally
      resultJSON.free;
    end;
  Finally
    json.Free;
  End;
end;

end.
