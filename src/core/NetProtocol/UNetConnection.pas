unit UNetConnection;

interface

uses
  Classes, UTCPIP, UOperationBlock, UTickCount, UThread, UAccountKey, UNetProtocolVersion, UOrderedRawList, UOperationsHashTree, UNetHeaderData, UNetTransferType, UPCOperationsComp;

type
  { TNetConnection }
  TNetConnection = Class
  private
    FIsConnecting: Boolean;
    FTcpIpClient : TNetTcpIpClient;
    FRemoteOperationBlock : TOperationBlock;
    FRemoteAccumulatedWork : UInt64;
    FLastDataReceivedTS : TTickCount;
    FLastDataSendedTS : TTickCount;
    FClientBufferRead : TStream;
    FIsWaitingForResponse : Boolean;
    FTimestampDiff : Integer;
    FIsMyselfServer : Boolean;
    FClientPublicKey : TAccountKey;
    FCreatedTime: TDateTime;
    FClientAppVersion: AnsiString;
    FDoFinalizeConnection : Boolean;
    FNetProtocolVersion: TNetProtocolVersion;
    FAlertedForNewProtocolAvailable : Boolean;
    FHasReceivedData : Boolean;
    FIsDownloadingBlocks : Boolean;
    FRandomWaitSecondsSendHello : Cardinal;
    FBufferLock : TPCCriticalSection;
    FBufferReceivedOperationsHash : TOrderedRawList;
    FBufferToSendOperations : TOperationsHashTree;
    FClientTimestampIp : AnsiString;
    function GetConnected: Boolean;
    procedure SetConnected(const Value: Boolean);
    procedure TcpClient_OnConnect(Sender: TObject);
    procedure TcpClient_OnDisconnect(Sender: TObject);
    Procedure DoProcess_Hello(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_Message(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_GetBlocks_Request(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_GetBlocks_Response(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_GetOperationsBlock_Request(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_NewBlock(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_AddOperations(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_GetSafeBox_Request(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_GetPendingOperations_Request(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_GetAccount_Request(HeaderData : TNetHeaderData; DataBuffer: TStream);
    Procedure DoProcess_GetPendingOperations;
    Function ReadTcpClientBuffer(MaxWaitMiliseconds : Cardinal; var HeaderData : TNetHeaderData; BufferData : TStream) : Boolean;
    function GetClient: TNetTcpIpClient;
  protected
//    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    Procedure Send(NetTranferType : TNetTransferType; operation, errorcode : Word; request_id : Integer; DataBuffer : TStream);
  public
    FNetLock : TPCCriticalSection;

    Constructor Create;
//    Constructor Create(AOwner : TComponent); override;
    Destructor Destroy; override;

    // Skybuck: moved to here to offer access to UNetServer
    procedure DoProcessBuffer;
    Procedure SetClient(Const Value : TNetTcpIpClient);
    Procedure SendError(NetTranferType : TNetTransferType; operation, request_id : Integer; error_code : Integer; error_text : AnsiString);

    // Skybuck: moved to here to offer access to UNetData
    Function DoSendAndWaitForResponse(operation: Word; RequestId: Integer; SendDataBuffer, ReceiveDataBuffer: TStream; MaxWaitTime : Cardinal; var HeaderData : TNetHeaderData) : Boolean;
    Procedure DisconnectInvalidClient(ItsMyself : Boolean; Const why : AnsiString);


    Function ConnectTo(ServerIP: String; ServerPort:Word) : Boolean;
    Property Connected : Boolean read GetConnected write SetConnected;
    Property IsConnecting : Boolean read FIsConnecting;
    Function Send_Hello(NetTranferType : TNetTransferType; request_id : Integer) : Boolean;
    Function Send_NewBlockFound(Const NewBlock : TPCOperationsComp) : Boolean;
    Function Send_GetBlocks(StartAddress, quantity : Cardinal; var request_id : Cardinal) : Boolean;
    Function Send_AddOperations(Operations : TOperationsHashTree) : Boolean;
    Function Send_Message(Const TheMessage : AnsiString) : Boolean;
    Function AddOperationsToBufferForSend(Operations : TOperationsHashTree) : Integer;
    Property Client : TNetTcpIpClient read GetClient;
    Function ClientRemoteAddr : AnsiString;
    property TimestampDiff : Integer read FTimestampDiff;
    property RemoteOperationBlock : TOperationBlock read FRemoteOperationBlock;
    //
    Property NetProtocolVersion : TNetProtocolVersion read FNetProtocolVersion;
    //
    Property IsMyselfServer : Boolean read FIsMyselfServer;
    Property CreatedTime : TDateTime read FCreatedTime;
    Property ClientAppVersion : AnsiString read FClientAppVersion write FClientAppVersion;

    // Skybuck: added to offer access for NetData
    Property DoFinalizeConnection : boolean read FDoFinalizeConnection;
//    Property NetLock : TPCCriticalSection read FNetLock; // Skybuck: *** problem *** FNetLock must be passed as a variable to some try lock function thus cannot use property, maybe if it's not a var may it work, there is probably no reason for it to be a var parameter, thus it's probably a design error, not sure yet though, documented it in UThread.pas see there for further reference.
    Property ClientPublicKey : TAccountKey read FClientPublicKey;
    Property TcpIpClient : TNetTcpIpClient read FTcpIpClient;
    Property HasReceivedData : Boolean read FHasReceivedData;

    // Skybuck: added property to offer access to UThreadGetNewBlockChainFromClient
    property RemoteAccumulatedWork : UInt64 read FRemoteAccumulatedWork;
    property IsDownloadingBlocks : boolean read FIsDownloadingBlocks;

    Procedure FinalizeConnection;

  End;

implementation

uses
  SysUtils, ULog, UNodeServerAddress, UConst, UNetData, UTime, UECDSA_Public, UPtrInt, UNetServerClient, UPlatform, UPCOperationClass, UPCOperation, UNode, UNetProtocolConst,
  UBlockAccount, URawBytes, UPCSafeBoxHeader, UStreamOp, UPascalCoinSafeBox, UCrypto, UPCChunk, UAccount, UAccountComp, UThreadGetNewBlockChainFromClient, UECIES, UNetClient, UPascalCoinBank;

{ TNetConnection }

function TNetConnection.AddOperationsToBufferForSend(Operations: TOperationsHashTree): Integer;
Var i : Integer;
begin
  Result := 0;
  try
    FBufferLock.Acquire;
    Try
      for i := 0 to Operations.OperationsCount - 1 do begin
        if FBufferReceivedOperationsHash.IndexOf(Operations.GetOperation(i).Sha256)<0 then begin
          FBufferReceivedOperationsHash.Add(Operations.GetOperation(i).Sha256);
          If FBufferToSendOperations.IndexOfOperation(Operations.GetOperation(i))<0 then begin
            FBufferToSendOperations.AddOperationToHashTree(Operations.GetOperation(i));
            Inc(Result);
          end;
        end;
      end;
    finally
      FBufferLock.Release;
    end;
  Except
    On E:Exception do begin
      TLog.NewLog(ltError,ClassName,'Error at AddOperationsToBufferForSend ('+E.ClassName+'): '+E.Message);
      Result := 0;
    end;
  end;
end;

function TNetConnection.ClientRemoteAddr: AnsiString;
begin
  If Assigned(FTcpIpClient) then begin
    Result := FtcpIpClient.ClientRemoteAddr
  end else Result := 'NIL';
end;

function TNetConnection.ConnectTo(ServerIP: String; ServerPort: Word) : Boolean;
Var nsa : TNodeServerAddress;
  lns : TList;
  i : Integer;
begin
  If FIsConnecting then Exit;
  Try
    FIsConnecting:=True;
    if Client.Connected then Client.Disconnect;
    TPCThread.ProtectEnterCriticalSection(Self,FNetLock);
    Try
      Client.RemoteHost := ServerIP;
      if ServerPort<=0 then ServerPort := CT_NetServer_Port;
      Client.RemotePort := ServerPort;
      TLog.NewLog(ltDebug,Classname,'Trying to connect to a server at: '+ClientRemoteAddr);
      PascalNetData.NodeServersAddresses.GetNodeServerAddress(Client.RemoteHost,Client.RemotePort,true,nsa);
      nsa.netConnection := Self;
      PascalNetData.NodeServersAddresses.SetNodeServerAddress(nsa);
      PascalNetData.NotifyNetConnectionUpdated;
      Result := Client.Connect;
    Finally
      FNetLock.Release;
    End;
    if Result then begin
      TLog.NewLog(ltDebug,Classname,'Connected to a possible server at: '+ClientRemoteAddr);
      PascalNetData.NodeServersAddresses.GetNodeServerAddress(Client.RemoteHost,Client.RemotePort,true,nsa);
      nsa.netConnection := Self;
      nsa.last_connection_by_me := (UnivDateTimeToUnix(DateTime2UnivDateTime(now)));
      PascalNetData.NodeServersAddresses.SetNodeServerAddress(nsa);
      Result := Send_Hello(ntp_request,PascalNetData.NewRequestId);
    end else begin
      TLog.NewLog(ltDebug,Classname,'Cannot connect to a server at: '+ClientRemoteAddr);
    end;
  finally
    FIsConnecting:=False;
  end;
end;

constructor TNetConnection.Create;
begin
  inherited;
  FIsConnecting:=False;
  FIsDownloadingBlocks := false;
  FHasReceivedData := false;
  FNetProtocolVersion.protocol_version := 0; // 0 = unknown
  FNetProtocolVersion.protocol_available := 0;
  FAlertedForNewProtocolAvailable := false;
  FDoFinalizeConnection := false;
  FClientAppVersion := '';
  FClientPublicKey := CT_TECDSA_Public_Nul;
  FCreatedTime := Now;
  FIsMyselfServer := false;
  FTimestampDiff := 0;
  FIsWaitingForResponse := false;
  FClientBufferRead := TMemoryStream.Create;
  FNetLock := TPCCriticalSection.Create('TNetConnection_NetLock');
  FLastDataReceivedTS := 0;
  FLastDataSendedTS := 0;
  FRandomWaitSecondsSendHello := 90 + Random(60);
  FTcpIpClient := Nil;
  FRemoteOperationBlock := CT_OperationBlock_NUL;
  FRemoteAccumulatedWork := 0;
  SetClient( TBufferedNetTcpIpClient.Create );
  PascalNetData.NetConnections.Add(Self);
  PascalNetData.NotifyNetConnectionUpdated;
  FBufferLock := TPCCriticalSection.Create('TNetConnection_BufferLock');
  FBufferReceivedOperationsHash := TOrderedRawList.Create;
  FBufferToSendOperations := TOperationsHashTree.Create;
  FClientTimestampIp := '';
end;

destructor TNetConnection.Destroy;
begin
  Try
    TLog.NewLog(ltdebug,ClassName,'Destroying '+Classname+' '+IntToHex(PtrInt(Self),8));

    Connected := false;

    PascalNetData.NodeServersAddresses.DeleteNetConnection(Self);
  Finally
    PascalNetData.NetConnections.Remove(Self);
  End;
  PascalNetData.UnRegisterRequest(Self,0,0);
  Try
    PascalNetData.NotifyNetConnectionUpdated;
  Finally
    FreeAndNil(FNetLock);
    FreeAndNil(FClientBufferRead);
    FreeAndNil(FTcpIpClient);
    FreeAndNil(FBufferLock);
    FreeAndNil(FBufferReceivedOperationsHash);
    FreeAndNil(FBufferToSendOperations);
    inherited;
  End;
end;

procedure TNetConnection.DisconnectInvalidClient(ItsMyself : Boolean; const why: AnsiString);
Var include_in_list : Boolean;
  ns : TNodeServerAddress;
begin
  FIsDownloadingBlocks := false;
  if ItsMyself then begin
    TLog.NewLog(ltInfo,Classname,'Disconecting myself '+ClientRemoteAddr+' > '+Why)
  end else begin
    TLog.NewLog(lterror,Classname,'Disconecting '+ClientRemoteAddr+' > '+Why);
  end;
  FIsMyselfServer := ItsMyself;
  include_in_list := (Not SameText(Client.RemoteHost,'localhost')) And (Not SameText(Client.RemoteHost,'127.0.0.1'))
    And (Not SameText('192.168.',Copy(Client.RemoteHost,1,8)))
    And (Not SameText('10.',Copy(Client.RemoteHost,1,3)));
  if include_in_list then begin
    If PascalNetData.NodeServersAddresses.GetNodeServerAddress(Client.RemoteHost,Client.RemotePort,true,ns) then begin
      ns.last_connection := UnivDateTimeToUnix(DateTime2UnivDateTime(now));
      ns.its_myself := ItsMyself;
      ns.BlackListText := Why;
      ns.is_blacklisted := true;
      PascalNetData.NodeServersAddresses.SetNodeServerAddress(ns);
    end;
  end else if ItsMyself then begin
    If PascalNetData.NodeServersAddresses.GetNodeServerAddress(Client.RemoteHost,Client.RemotePort,true,ns) then begin
      ns.its_myself := ItsMyself;
      PascalNetData.NodeServersAddresses.SetNodeServerAddress(ns);
    end;
  end;
  Connected := False;
  PascalNetData.NotifyBlackListUpdated;
  PascalNetData.NotifyNodeServersUpdated;
end;

procedure TNetConnection.DoProcessBuffer;
Var HeaderData : TNetHeaderData;
  ms : TMemoryStream;
  ops : AnsiString;
begin
  if FDoFinalizeConnection then begin
    TLog.NewLog(ltdebug,Classname,'Executing DoFinalizeConnection at client '+ClientRemoteAddr);
    Connected := false;
  end;
  if Not Connected then exit;
  ms := TMemoryStream.Create;
  try
    if Not FIsWaitingForResponse then begin
      DoSendAndWaitForResponse(0,0,Nil,ms,0,HeaderData);
    end;
  finally
    ms.Free;
  end;
  If ((FLastDataReceivedTS>0) Or ( NOT (Self is TNetServerClient)))
     AND ((FLastDataReceivedTS+(1000*FRandomWaitSecondsSendHello)<TPlatform.GetTickCount) AND (FLastDataSendedTS+(1000*FRandomWaitSecondsSendHello)<TPlatform.GetTickCount)) then begin
     // Build 1.4 -> Changing wait time from 120 secs to a random seconds value
    If PascalNetData.PendingRequest(Self,ops)>=2 then begin
      TLog.NewLog(ltDebug,Classname,'Pending requests without response... closing connection to '+ClientRemoteAddr+' > '+ops);
      Connected := false;
    end else begin
      TLog.NewLog(ltDebug,Classname,'Sending Hello to check connection to '+ClientRemoteAddr+' > '+ops);
      Send_Hello(ntp_request,PascalNetData.NewRequestId);
    end;
  end else if (Self is TNetServerClient) AND (FLastDataReceivedTS=0) And (FCreatedTime+EncodeTime(0,1,0,0)<Now) then begin
    // Disconnecting client without data...
    TLog.NewLog(ltDebug,Classname,'Disconnecting client without data '+ClientRemoteAddr);
    Connected := false;
  end;
end;

procedure TNetConnection.DoProcess_AddOperations(HeaderData: TNetHeaderData; DataBuffer: TStream);
var c,i : Integer;
    optype : Byte;
    opclass : TPCOperationClass;
    op : TPCOperation;
    operations : TOperationsHashTree;
    errors : AnsiString;
  DoDisconnect : Boolean;
begin
  DoDisconnect := true;
  operations := TOperationsHashTree.Create;
  try
    if HeaderData.header_type<>ntp_autosend then begin
      errors := 'Not autosend';
      exit;
    end;
    if DataBuffer.Size<4 then begin
      errors := 'Invalid databuffer size';
      exit;
    end;
    DataBuffer.Read(c,4);
    for i := 1 to c do begin
      errors := 'Invalid operation '+inttostr(i)+'/'+inttostr(c);
      if not DataBuffer.Read(optype,1)=1 then exit;
      opclass := TPCOperationsComp.GetOperationClassByOpType(optype);
      if Not Assigned(opclass) then exit;
      op := opclass.Create;
      Try
        op.LoadFromNettransfer(DataBuffer);
        operations.AddOperationToHashTree(op);
      Finally
        op.Free;
      End;
    end;
    DoDisconnect := false;
  finally
    try
      if DoDisconnect then begin
        DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
      end else begin
        // Add to received buffer
        FBufferLock.Acquire;
        Try
          for i := 0 to operations.OperationsCount - 1 do begin
            op := operations.GetOperation(i);
            FBufferReceivedOperationsHash.Add(op.Sha256);
            c := FBufferToSendOperations.IndexOfOperation(op);
            if (c>=0) then begin
              FBufferToSendOperations.Delete(c);
            end;
          end;
        Finally
          FBufferLock.Release;
        End;
        PascalCoinNode.AddOperations(Self,operations,Nil,errors);
      end;
    finally
      operations.Free;
    end;
  end;
end;

procedure TNetConnection.DoProcess_GetBlocks_Request(HeaderData: TNetHeaderData; DataBuffer: TStream);
Var b,b_start,b_end:Cardinal;
    op : TPCOperationsComp;
    db : TMemoryStream;
    c : Cardinal;
  errors : AnsiString;
  DoDisconnect : Boolean;
  posquantity : Int64;
begin
  DoDisconnect := true;
  try
    if HeaderData.header_type<>ntp_request then begin
      errors := 'Not request';
      exit;
    end;
     // DataBuffer contains: from and to
     errors := 'Invalid structure';
     if (DataBuffer.Size-DataBuffer.Position<8) then begin
       exit;
     end;
     DataBuffer.Read(b_start,4);
     DataBuffer.Read(b_end,4);
     if (b_start<0) Or (b_start>b_end) then begin
       errors := 'Invalid structure start or end: '+Inttostr(b_start)+' '+Inttostr(b_end);
       exit;
     end;
     if (b_end>=PascalCoinSafeBox.BlocksCount) then begin
       b_end := PascalCoinSafeBox.BlocksCount-1;
       if (b_start>b_end) then begin
         // No data:
         db := TMemoryStream.Create;
         try
           c := 0;
           db.Write(c,4);
           Send(ntp_response,HeaderData.operation,0,HeaderData.request_id,db);
           Exit;
         finally
           db.Free;
         end;
       end;
     end;

     DoDisconnect := false;

     db := TMemoryStream.Create;
     try

       op := TPCOperationsComp.Create;
       try
         c := b_end - b_start + 1;
         posquantity := db.position;
         db.Write(c,4);
         c := 0;
         b := b_start;
         for b := b_start to b_end do begin
           inc(c);
           If PascalCoinBank.LoadOperations(op,b) then begin
             op.SaveBlockToStream(false,db);
           end else begin
             SendError(ntp_response,HeaderData.operation,HeaderData.request_id,CT_NetError_InternalServerError,'Operations of block:'+inttostr(b)+' not found');
             exit;
           end;
           // Build 1.0.5 To prevent high data over net in response (Max 2 Mb of data)
           if (db.size>(1024*1024*2)) then begin
             // Stop
             db.position := posquantity;
             db.Write(c,4);
             // BUG of Build 1.0.5 !!! Need to break bucle OH MY GOD!
             db.Position := db.Size;
             break;
           end;
         end;
         Send(ntp_response,HeaderData.operation,0,HeaderData.request_id,db);
       finally
         op.Free;
       end;
     finally
       db.Free;
     end;
     TLog.NewLog(ltdebug,Classname,'Sending operations from block '+inttostr(b_start)+' to '+inttostr(b_end));
  finally
    if DoDisconnect then begin
      DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
    end;
  end;
end;

procedure TNetConnection.DoProcess_GetBlocks_Response(HeaderData: TNetHeaderData; DataBuffer: TStream);
  var op : TPCOperationsComp;
    opcount,i : Cardinal;
    newBlockAccount : TBlockAccount;
  errors : AnsiString;
  DoDisconnect : Boolean;
begin
  DoDisconnect := true;
  try
    if HeaderData.header_type<>ntp_response then begin
      errors := 'Not response';
      exit;
    end;
    If HeaderData.is_error then begin
      DoDisconnect := false;
      exit; //
    end;
    // DataBuffer contains: from and to
    errors := 'Invalid structure';
    op := TPCOperationsComp.Create;
    Try
      if DataBuffer.Size-DataBuffer.Position<4 then begin
        DisconnectInvalidClient(false,'DoProcess_GetBlocks_Response invalid format: '+errors);
        exit;
      end;
      DataBuffer.Read(opcount,4);
      DoDisconnect :=false;
      for I := 1 to opcount do begin
        if Not op.LoadBlockFromStream(DataBuffer,errors) then begin
           errors := 'Error decoding block '+inttostr(i)+'/'+inttostr(opcount)+' Errors:'+errors;
           DoDisconnect := true;
           exit;
        end;
        if (op.OperationBlock.block=PascalCoinSafeBox.BlocksCount) then begin
          if (PascalCoinBank.AddNewBlockChainBlock(op,PascalNetData.NetworkAdjustedTime.GetMaxAllowedTimestampForNewBlock, newBlockAccount,errors)) then begin
            // Ok, one more!
          end else begin
            // Is not a valid entry????
            // Perhaps an orphan blockchain: Me or Client!
            TLog.NewLog(ltinfo,Classname,'Distinct operation block found! My:'+
                TPCOperationsComp.OperationBlockToText(PascalCoinSafeBox.Block(PascalCoinSafeBox.BlocksCount-1).blockchainInfo)+
                ' remote:'+TPCOperationsComp.OperationBlockToText(op.OperationBlock)+' Errors: '+errors);
          end;
        end else begin
          // Receiving an unexpected operationblock
          TLog.NewLog(lterror,classname,'Received a distinct block, finalizing: '+TPCOperationsComp.OperationBlockToText(op.OperationBlock)+' (My block: '+TPCOperationsComp.OperationBlockToText(PascalCoinBank.LastOperationBlock)+')' );
          FIsDownloadingBlocks := false;
          exit;
        end;
      end;
      FIsDownloadingBlocks := false;
      if ((opcount>0) And (FRemoteOperationBlock.block>=PascalCoinSafeBox.BlocksCount)) then begin
        Send_GetBlocks(PascalCoinSafeBox.BlocksCount,100,i);
      end else begin
        // No more blocks to download, download Pending operations
        DoProcess_GetPendingOperations;
      end;
      PascalCoinNode.NotifyBlocksChanged;
    Finally
      op.Free;
    End;
  Finally
    if DoDisconnect then begin
      DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
    end;
  end;
end;

procedure TNetConnection.DoProcess_GetOperationsBlock_Request(HeaderData: TNetHeaderData; DataBuffer: TStream);
Const CT_Max_Positions = 10;
Var inc_b,b,b_start,b_end, total_b:Cardinal;
  db,msops : TMemoryStream;
  errors, blocksstr : AnsiString;
  DoDisconnect : Boolean;
  ob : TOperationBlock;
begin
  blocksstr := '';
  DoDisconnect := true;
  try
    if HeaderData.header_type<>ntp_request then begin
      errors := 'Not request';
      exit;
    end;
    errors := 'Invalid structure';
    if (DataBuffer.Size-DataBuffer.Position<8) then begin
       exit;
    end;
    DataBuffer.Read(b_start,4);
    DataBuffer.Read(b_end,4);
    if (b_start<0) Or (b_start>b_end) Or (b_start>=PascalCoinSafeBox.BlocksCount) then begin
      errors := 'Invalid start ('+Inttostr(b_start)+') or end ('+Inttostr(b_end)+') of count ('+Inttostr(PascalCoinSafeBox.BlocksCount)+')';
      exit;
    end;

    DoDisconnect := false;

    if (b_end>=PascalCoinSafeBox.BlocksCount) then b_end := PascalCoinSafeBox.BlocksCount-1;
    inc_b := ((b_end - b_start) DIV CT_Max_Positions)+1;
    msops := TMemoryStream.Create;
    try
      b := b_start;
      total_b := 0;
      repeat
        ob := PascalCoinSafeBox.Block(b).blockchainInfo;
        If TPCOperationsComp.SaveOperationBlockToStream(ob,msops) then begin
          blocksstr := blocksstr + inttostr(b)+',';
          b := b + inc_b;
          inc(total_b);
        end else begin
          errors := 'ERROR DEV 20170522-1 block:'+inttostr(b);
          SendError(ntp_response,HeaderData.operation,HeaderData.request_id,CT_NetError_InternalServerError,errors);
          exit;
        end;
      until (b > b_end);
      db := TMemoryStream.Create;
      try
       db.Write(total_b,4);
       db.WriteBuffer(msops.Memory^,msops.Size);
       Send(ntp_response,HeaderData.operation,0,HeaderData.request_id,db);
      finally
       db.Free;
      end;
    finally
      msops.Free;
    end;
    TLog.NewLog(ltdebug,Classname,'Sending '+inttostr(total_b)+' operations block from block '+inttostr(b_start)+' to '+inttostr(b_end)+' '+blocksstr);
  finally
    if DoDisconnect then begin
      DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
    end;
  end;
end;

procedure TNetConnection.DoProcess_GetSafeBox_Request(HeaderData: TNetHeaderData; DataBuffer: TStream);
Var _blockcount : Cardinal;
    _safeboxHash : TRawBytes;
    _from,_to : Cardinal;
  sbStream : TStream;
  responseStream : TStream;
  antPos : Int64;
  sbHeader : TPCSafeBoxHeader;
  errors : AnsiString;
begin
  {
  This call is used to obtain a chunk of the safebox
  Request:
  BlockCount (4 bytes) - The safebox checkpoint
  SafeboxHash (AnsiString) - The safeboxhash of that checkpoint
  StartPos (4 bytes) - The start index (0..BlockCount-1)
  EndPos   (4 bytes) - The final index (0..BlockCount-1)
    If valid info:
      - If available will return a LZIP chunk of safebox
      - If not available (requesting for an old safebox) will retun not available
    If not valid will disconnect
  }
  DataBuffer.Read(_blockcount,SizeOf(_blockcount));
  TStreamOp.ReadAnsiString(DataBuffer,_safeboxHash);
  DataBuffer.Read(_from,SizeOf(_from));
  DataBuffer.Read(_to,SizeOf(_to));
  //
  sbStream := PascalCoinBank.Storage.CreateSafeBoxStream(_blockcount);
  try
    responseStream := TMemoryStream.Create;
    try
      If Not Assigned(sbStream) then begin
        SendError(ntp_response,HeaderData.operation,CT_NetError_SafeboxNotFound,HeaderData.request_id,Format('Safebox for block %d not found',[_blockcount]));
        exit;
      end;
      antPos := sbStream.Position;
      TPCSafeBox.LoadSafeBoxStreamHeader(sbStream,sbHeader);
      If sbHeader.safeBoxHash<>_safeboxHash then begin
        DisconnectInvalidClient(false,Format('Invalid safeboxhash on GetSafeBox request (Real:%s > Requested:%s)',[TCrypto.ToHexaString(sbHeader.safeBoxHash),TCrypto.ToHexaString(_safeboxHash)]));
        exit;
      end;
      // Response:
      sbStream.Position:=antPos;
      If not TPCChunk.SaveSafeBoxChunkFromSafeBox(sbStream,responseStream,_from,_to,errors) then begin
        TLog.NewLog(ltError,Classname,'Error saving chunk: '+errors);
        exit;
      end;
      // Sending
      Send(ntp_response,HeaderData.operation,0,HeaderData.request_id,responseStream);
      TLog.NewLog(ltInfo,ClassName,Format('Sending Safebox(%d) chunk[%d..%d] to %s Bytes:%d',[_blockcount,_from,_to,ClientRemoteAddr,responseStream.Size]));
    finally
      responseStream.Free;
    end;
  finally
    FreeAndNil(sbStream);
  end;
end;

procedure TNetConnection.DoProcess_GetPendingOperations_Request(HeaderData: TNetHeaderData; DataBuffer: TStream);
var responseStream : TMemoryStream;
  i,start,max : Integer;
  b : Byte;
  c : Cardinal;
  DoDisconnect : Boolean;
  errors : AnsiString;
  opht : TOperationsHashTree;
begin
  {
  This call is used to obtain pending operations not included in blockchain
  Request:
  - Request type (1 byte) - Values
    - Value 1:
      Returns Count
    - Value 2:
      - start (4 bytes)
      - max (4 bytes)
      Returns Pending operations (from start to start+max) in a TOperationsHashTree Stream
  }
  errors := '';
  DoDisconnect := true;
  responseStream := TMemoryStream.Create;
  try
    if HeaderData.header_type<>ntp_request then begin
      errors := 'Not request';
      exit;
    end;
    DataBuffer.Read(b,1);
    if (b=1) then begin
      // Return count
      c := PascalCoinNode.Operations.Count;
      responseStream.Write(c,SizeOf(c));
    end else if (b=2) then begin
      // Return from start to start+max
      DataBuffer.Read(c,SizeOf(c)); // Start 4 bytes
      start:=c;
      DataBuffer.Read(c,SizeOf(c)); // max 4 bytes
      max:=c;
      //
      if (start<0) Or (max<0) then begin
        errors := 'Invalid start/max value';
        Exit;
      end;
      opht := TOperationsHashTree.Create;
      Try
        PascalCoinNode.Operations.Lock;
        Try
          if (start >= PascalCoinNode.Operations.Count) Or (max=0) then begin
          end else begin
            if (start + max >= PascalCoinNode.Operations.Count) then max := PascalCoinNode.Operations.Count - start;
            for i:=start to (start + max -1) do begin
              opht.AddOperationToHashTree(PascalCoinNode.Operations.OperationsHashTree.GetOperation(i));
            end;
          end;
        finally
          PascalCoinNode.Operations.Unlock;
        end;
        opht.SaveOperationsHashTreeToStream(responseStream,False);
      Finally
        opht.Free;
      End;
    end else begin
      errors := 'Invalid call type '+inttostr(b);
      Exit;
    end;
    DoDisconnect:=False;
    Send(ntp_response,HeaderData.operation,0,HeaderData.request_id,responseStream);
  finally
    responseStream.Free;
    if DoDisconnect then begin
      DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
    end;
  end;
end;

procedure TNetConnection.DoProcess_GetPendingOperations;
Var dataSend, dataReceived : TMemoryStream;
  request_id, cStart, cMax, cTotal, cTotalByOther, cReceived, cAddedOperations : Cardinal;
  b : Byte;
  headerData : TNetHeaderData;
  opht : TOperationsHashTree;
  errors : AnsiString;
  i : Integer;
begin
  {$IFDEF PRODUCTION}
  If FNetProtocolVersion.protocol_available<=6 then Exit; // Note: GetPendingOperations started on protocol_available=7
  {$ENDIF}
  request_id := 0;
  cAddedOperations := 0;
  if Not Connected then exit;
  // First receive operations from
  dataSend := TMemoryStream.Create;
  dataReceived := TMemoryStream.Create;
  try
    b := 1;
    dataSend.Write(b,1);
    request_id := PascalNetData.NewRequestId;
    If Not DoSendAndWaitForResponse(CT_NetOp_GetPendingOperations,request_id,dataSend,dataReceived,20000,headerData) then begin
      Exit;
    end;
    dataReceived.Position:=0;
    cTotalByOther := 0;
    If (dataReceived.Read(cTotalByOther,SizeOf(cTotal))<SizeOf(cTotal)) then begin
      DisconnectInvalidClient(False,'Invalid data returned on GetPendingOperations');
      Exit;
    end;
    cTotal := cTotalByOther;
    if (cTotal>5000) then begin
      // Limiting max pending operations to 5000
      cTotal := 5000;
    end;
    cReceived:=0;
    cStart := 0;
    While (Connected) And (cReceived<cTotal) do begin
      dataSend.Clear;
      dataReceived.Clear;
      b := 2;
      dataSend.Write(b,1);
      dataSend.Write(cStart,SizeOf(cStart));
      cMax := 1000;  // Limiting in 1000 by round
      dataSend.Write(cMax,SizeOf(cMax));
      request_id := PascalNetData.NewRequestId;
      If Not DoSendAndWaitForResponse(CT_NetOp_GetPendingOperations,request_id,dataSend,dataReceived,50000,headerData) then begin
        Exit;
      end;
      dataReceived.Position:=0;
      //
      opht := TOperationsHashTree.Create;
      try
        If Not opht.LoadOperationsHashTreeFromStream(dataReceived,False,0,Nil,errors) then begin
          DisconnectInvalidClient(False,'Invalid operations hash tree stream: '+errors);
          Exit;
        end;
        If (opht.OperationsCount>0) then begin
          inc(cReceived,opht.OperationsCount);
          i := PascalCoinNode.AddOperations(Self,opht,Nil,errors);
          inc(cAddedOperations,i);
        end else Break; // No more
        inc(cStart,opht.OperationsCount);
      finally
        opht.Free;
      end;
    end;
    TLog.NewLog(ltInfo,Classname,Format('Processed GetPendingOperations to %s obtaining %d (available %d) operations and added %d to Node',
      [Self.ClientRemoteAddr,cTotal,cTotalByOther,cAddedOperations]));
  finally
    dataSend.Free;
    dataReceived.Free;
  end;
end;

procedure TNetConnection.DoProcess_GetAccount_Request(HeaderData: TNetHeaderData; DataBuffer: TStream);
Const CT_Max_Accounts_per_call = 1000;
var responseStream : TMemoryStream;
  i,start,max : Integer;
  b : Byte;
  c : Cardinal;
  acc : TAccount;
  DoDisconnect : Boolean;
  errors : AnsiString;
begin
  {
  This call is used to obtain an Account data
    - Also will return current node block number
    - If a returned data has updated_block value = (current block+1) that means that Account is currently affected by a pending operation in the pending operations
  Request:
  Request type (1 byte) - Values
    - Value 1: Single account
    - Value 2: From account start to start+max  LIMITED AT MAX 1000
    - Value 3: Multiple accounts LIMITED AT MAX 1000
  On 1:
    - account (4 bytes)
  On 2:
    - start (4 bytes)
    - max (4 bytes)
  On 3:
    - count (4 bytes)
    - for 1 to count read account (4 bytes)
  Returns:
  - current block number (4 bytes): Note, if an account has updated_block > current block means that has been updated and is in pending state
  - count (4 bytes)
  - for 1 to count:  TAccountComp.SaveAccountToAStream
  }
  errors := '';
  DoDisconnect := true;
  responseStream := TMemoryStream.Create;
  try
    // Response first 4 bytes are current block number
    c := PascalCoinSafeBox.BlocksCount-1;
    responseStream.Write(c,SizeOf(c));
    //
    if HeaderData.header_type<>ntp_request then begin
      errors := 'Not request';
      exit;
    end;
    if (DataBuffer.Size-DataBuffer.Position<5) then begin
      errors := 'Invalid structure';
      exit;
    end;
    DataBuffer.Read(b,1);
    if (b in [1,2]) then begin
      if (b=1) then begin
        DataBuffer.Read(c,SizeOf(c));
        start:=c;
        max:=1; // Bug 3.0.1 (was c instead of fixed 1)
      end else begin
        DataBuffer.Read(c,SizeOf(c));
        start:=c;
        DataBuffer.Read(c,SizeOf(c));
        max:=c;
      end;
      If max>CT_Max_Accounts_per_call then max := CT_Max_Accounts_per_call;
      if (start<0) Or (max<0) then begin
        errors := 'Invalid start/max value';
        Exit;
      end;
      if (start >= PascalCoinSafeBox.AccountsCount) Or (max=0) then begin
        c := 0;
        responseStream.Write(c,SizeOf(c));
      end else begin
        if (start + max >= PascalCoinSafeBox.AccountsCount) then max := PascalCoinSafeBox.AccountsCount - start;
        c := max;
        responseStream.Write(c,SizeOf(c));
        for i:=start to (start + max -1) do begin
          acc := PascalCoinNode.Operations.SafeBoxTransaction.Account(i);
          TAccountComp.SaveAccountToAStream(responseStream,acc);
        end;
      end;
    end else if (b=3) then begin
      DataBuffer.Read(c,SizeOf(c));
      if (c>CT_Max_Accounts_per_call) then c := CT_Max_Accounts_per_call;
      responseStream.Write(c,SizeOf(c));
      max := c;
      for i:=1 to max do begin
        DataBuffer.Read(c,SizeOf(c));
        if (c>=0) And (c<PascalCoinSafeBox.AccountsCount) then begin
          acc := PascalCoinNode.Operations.SafeBoxTransaction.Account(c);
          TAccountComp.SaveAccountToAStream(responseStream,acc);
        end else begin
          errors := 'Invalid account number '+Inttostr(c);
          Exit;
        end;
      end;
    end else begin
      errors := 'Invalid call type '+inttostr(b);
      Exit;
    end;
    DoDisconnect:=False;
    Send(ntp_response,HeaderData.operation,0,HeaderData.request_id,responseStream);
  finally
    responseStream.Free;
    if DoDisconnect then begin
      DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
    end;
  end;
end;

procedure TNetConnection.DoProcess_Hello(HeaderData: TNetHeaderData; DataBuffer: TStream);
var op, myLastOp : TPCOperationsComp;
    errors : AnsiString;
    connection_has_a_server : Word;
    i,c : Integer;
    nsa : TNodeServerAddress;
    rid : Cardinal;
    connection_ts : Cardinal;
   Duplicate : TNetConnection;
   RawAccountKey : TRawBytes;
   other_version : AnsiString;
   isFirstHello : Boolean;
   lastTimestampDiff : Integer;
Begin
  FRemoteAccumulatedWork := 0;
  op := TPCOperationsComp.Create;
  try
    DataBuffer.Position:=0;
    if DataBuffer.Read(connection_has_a_server,2)<2 then begin
      DisconnectInvalidClient(false,'Invalid data on buffer: '+TNetData.HeaderDataToText(HeaderData));
      exit;
    end;
    If TStreamOp.ReadAnsiString(DataBuffer,RawAccountKey)<0 then begin
      DisconnectInvalidClient(false,'Invalid data on buffer. No Public key: '+TNetData.HeaderDataToText(HeaderData));
      exit;
    end;
    FClientPublicKey := TAccountComp.RawString2Accountkey(RawAccountKey);
    If Not TAccountComp.IsValidAccountKey(FClientPublicKey,errors) then begin
      DisconnectInvalidClient(false,'Invalid Public key: '+TNetData.HeaderDataToText(HeaderData)+' errors: '+errors);
      exit;
    end;
    if DataBuffer.Read(connection_ts,4)<4 then begin
      DisconnectInvalidClient(false,'Invalid data on buffer. No TS: '+TNetData.HeaderDataToText(HeaderData));
      exit;
    end;
    lastTimestampDiff := FTimestampDiff;
    FTimestampDiff := Integer( Int64(connection_ts) - Int64(PascalNetData.NetworkAdjustedTime.GetAdjustedTime) );
    If FClientTimestampIp='' then begin
      isFirstHello := True;
      FClientTimestampIp := FTcpIpClient.RemoteHost;
      PascalNetData.NetworkAdjustedTime.AddNewIp(FClientTimestampIp,connection_ts);
      if (Abs(PascalNetData.NetworkAdjustedTime.TimeOffset)>CT_MaxFutureBlockTimestampOffset) then begin
        PascalCoinNode.NotifyNetClientMessage(Nil,'The detected network time is different from this system time in '+
          IntToStr(PascalNetData.NetworkAdjustedTime.TimeOffset)+' seconds! Please check your local time/timezone');
      end;
      if (Abs(FTimestampDiff) > CT_MaxFutureBlockTimestampOffset) then begin
        TLog.NewLog(ltDebug,ClassName,'Detected a node ('+ClientRemoteAddr+') with incorrect timestamp: '+IntToStr(connection_ts)+' offset '+IntToStr(FTimestampDiff) );
      end;
    end else begin
      isFirstHello := False;
      PascalNetData.NetworkAdjustedTime.UpdateIp(FClientTimestampIp,connection_ts);
    end;
    If (Abs(lastTimestampDiff) > CT_MaxFutureBlockTimestampOffset) And (Abs(FTimestampDiff) <= CT_MaxFutureBlockTimestampOffset) then begin
      TLog.NewLog(ltDebug,ClassName,'Corrected timestamp for node ('+ClientRemoteAddr+') old offset: '+IntToStr(lastTimestampDiff)+' current offset '+IntToStr(FTimestampDiff) );
    end;

    if (connection_has_a_server>0) And (Not SameText(Client.RemoteHost,'localhost')) And (Not SameText(Client.RemoteHost,'127.0.0.1'))
      And (Not SameText('192.168.',Copy(Client.RemoteHost,1,8)))
      And (Not SameText('10.',Copy(Client.RemoteHost,1,3)))
      And (Not TAccountComp.EqualAccountKeys(FClientPublicKey,PascalNetData.NodePrivateKey.PublicKey)) then begin
      nsa := CT_TNodeServerAddress_NUL;
      nsa.ip := Client.RemoteHost;
      nsa.port := connection_has_a_server;
      nsa.last_connection := UnivDateTimeToUnix(DateTime2UnivDateTime(now));
      PascalNetData.AddServer(nsa);
    end;

    if op.LoadBlockFromStream(DataBuffer,errors) then begin
      FRemoteOperationBlock := op.OperationBlock;
      if (DataBuffer.Size-DataBuffer.Position>=4) then begin
        DataBuffer.Read(c,4);
        for i := 1 to c do begin
          nsa := CT_TNodeServerAddress_NUL;
          TStreamOp.ReadAnsiString(DataBuffer,nsa.ip);
          DataBuffer.Read(nsa.port,2);
          DataBuffer.Read(nsa.last_connection_by_server,4);
          If (nsa.last_connection_by_server>0) And (i<=CT_MAX_NODESERVERS_ON_HELLO) then // Protect massive data
            PascalNetData.AddServer(nsa);
        end;
        if TStreamOp.ReadAnsiString(DataBuffer,other_version)>=0 then begin
          // Captures version
          ClientAppVersion := other_version;
          if (DataBuffer.Size-DataBuffer.Position>=SizeOf(FRemoteAccumulatedWork)) then begin
            DataBuffer.Read(FRemoteAccumulatedWork,SizeOf(FRemoteAccumulatedWork));
            TLog.NewLog(ltdebug,ClassName,'Received HELLO with height: '+inttostr(op.OperationBlock.block)+' Accumulated work '+IntToStr(FRemoteAccumulatedWork));
          end;
        end;
        //
        if (FRemoteAccumulatedWork>PascalCoinSafeBox.WorkSum) Or
          ((FRemoteAccumulatedWork=0) And (PascalNetData.MaxRemoteOperationBlock.block<FRemoteOperationBlock.block)) then begin
          PascalNetData.MaxRemoteOperationBlock := FRemoteOperationBlock;
          if TPCThread.ThreadClassFound(TThreadGetNewBlockChainFromClient,nil)<0 then begin
            TThreadGetNewBlockChainFromClient.Create;
          end;
        end;
      end;

      TLog.NewLog(ltdebug,Classname,'Hello received: '+TPCOperationsComp.OperationBlockToText(FRemoteOperationBlock));
      if (HeaderData.header_type in [ntp_request,ntp_response]) then begin
        // Response:
        if (HeaderData.header_type=ntp_request) then begin
          Send_Hello(ntp_response,HeaderData.request_id);
        end;

        // Protection of invalid timestamp when is a new incoming connection due to wait time
        if (isFirstHello) And (Self is TNetServerClient) and (HeaderData.header_type=ntp_request) and (Abs(FTimestampDiff) > CT_MaxFutureBlockTimestampOffset) then begin
          TLog.NewLog(ltDebug,ClassName,'Sending HELLO again to ('+ClientRemoteAddr+') in order to check invalid current Timestamp offset: '+IntToStr(FTimestampDiff) );
          Send_Hello(ntp_request,PascalNetData.NewRequestId);
        end;

        if (TAccountComp.EqualAccountKeys(FClientPublicKey,PascalNetData.NodePrivateKey.PublicKey)) then begin
          DisconnectInvalidClient(true,'MySelf disconnecting...');
          exit;
        end;
        Duplicate := PascalNetData.FindConnectionByClientRandomValue(Self);
        if (Duplicate<>Nil) And (Duplicate.Connected) then begin
          DisconnectInvalidClient(true,'Duplicate connection with '+Duplicate.ClientRemoteAddr);
          exit;
        end;
        PascalNetData.NotifyReceivedHelloMessage;
      end else begin
        DisconnectInvalidClient(false,'Invalid header type > '+TNetData.HeaderDataToText(HeaderData));
      end;
      //
      If (isFirstHello) And (HeaderData.header_type = ntp_response) then begin
        DoProcess_GetPendingOperations;
      end;
    end else begin
      TLog.NewLog(lterror,Classname,'Error decoding operations of HELLO: '+errors);
      DisconnectInvalidClient(false,'Error decoding operations of HELLO: '+errors);
    end;
  finally
    op.Free;
  end;
end;

procedure TNetConnection.DoProcess_Message(HeaderData: TNetHeaderData; DataBuffer: TStream);
Var   errors : AnsiString;
  decrypted,messagecrypted : AnsiString;
  DoDisconnect : boolean;
begin
  errors := '';
  DoDisconnect := true;
  try
    if HeaderData.header_type<>ntp_autosend then begin
      errors := 'Not autosend';
      exit;
    end;
    If TStreamOp.ReadAnsiString(DataBuffer,messagecrypted)<0 then begin
      errors := 'Invalid message data';
      exit;
    end;
    If Not ECIESDecrypt(PascalNetData.NodePrivateKey.EC_OpenSSL_NID,PascalNetData.NodePrivateKey.PrivateKey,false,messagecrypted,decrypted) then begin
      errors := 'Error on decrypting message';
      exit;
    end;

    DoDisconnect := false;
    if TCrypto.IsHumanReadable(decrypted) then
      TLog.NewLog(ltinfo,Classname,'Received new message from '+ClientRemoteAddr+' Message ('+inttostr(length(decrypted))+' bytes): '+decrypted)
    else
      TLog.NewLog(ltinfo,Classname,'Received new message from '+ClientRemoteAddr+' Message ('+inttostr(length(decrypted))+' bytes) in hexadecimal: '+TCrypto.ToHexaString(decrypted));
    Try
      PascalCoinNode.NotifyNetClientMessage(Self,decrypted);
    Except
      On E:Exception do begin
        TLog.NewLog(lterror,Classname,'Error processing received message. '+E.ClassName+' '+E.Message);
      end;
    end;
  finally
    if DoDisconnect then begin
      DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
    end;
  end;
end;

procedure TNetConnection.DoProcess_NewBlock(HeaderData: TNetHeaderData; DataBuffer: TStream);
var bacc : TBlockAccount;
    op : TPCOperationsComp;
  errors : AnsiString;
  DoDisconnect : Boolean;
begin
  errors := '';
  DoDisconnect := true;
  try
    if HeaderData.header_type<>ntp_autosend then begin
      errors := 'Not autosend';
      exit;
    end;
    op := TPCOperationsComp.Create;
    try
      if Not op.LoadBlockFromStream(DataBuffer,errors) then begin
        errors := 'Error decoding new account: '+errors;
        exit;
      end else begin
        DoDisconnect := false;
        if DataBuffer.Size - DataBuffer.Position >= SizeOf(FRemoteAccumulatedWork) then begin
          DataBuffer.Read(FRemoteAccumulatedWork,SizeOf(FRemoteAccumulatedWork));
          TLog.NewLog(ltdebug,ClassName,'Received NEW BLOCK with height: '+inttostr(op.OperationBlock.block)+' Accumulated work '+IntToStr(FRemoteAccumulatedWork));
        end else FRemoteAccumulatedWork := 0;
        FRemoteOperationBlock := op.OperationBlock;
        //
        if FRemoteAccumulatedWork=0 then begin
          // Old version. No data
          if (op.OperationBlock.block>PascalCoinSafeBox.BlocksCount) then begin
            PascalNetData.GetNewBlockChainFromClient(Self,Format('BlocksCount:%d > my BlocksCount:%d',[op.OperationBlock.block+1,PascalCoinSafeBox.BlocksCount]));
          end else if (op.OperationBlock.block=PascalCoinSafeBox.BlocksCount) then begin
            // New block candidate:
            If Not PascalCoinNode.AddNewBlockChain(Self,op,bacc,errors) then begin
              // Received a new invalid block... perhaps I'm an orphan blockchain
              PascalNetData.GetNewBlockChainFromClient(Self,'Has a distinct block. '+errors);
            end;
          end;
        end else begin
          if (FRemoteAccumulatedWork>PascalCoinSafeBox.WorkSum) then begin
            if (op.OperationBlock.block=PascalCoinSafeBox.BlocksCount) then begin
              // New block candidate:
              If Not PascalCoinNode.AddNewBlockChain(Self,op,bacc,errors) then begin
                // Really is a new block? (Check it)
                if (op.OperationBlock.block=PascalCoinSafeBox.BlocksCount) then begin
                  // Received a new invalid block... perhaps I'm an orphan blockchain
                  PascalNetData.GetNewBlockChainFromClient(Self,'Higher Work with same block height. I''m a orphan blockchain candidate');
                end;
              end;
            end else begin
              // Received a new higher work
              PascalNetData.GetNewBlockChainFromClient(Self,Format('Higher Work and distinct blocks count. Need to download BlocksCount:%d  my BlocksCount:%d',[op.OperationBlock.block+1,PascalCoinSafeBox.BlocksCount]));
            end;
          end;
        end;
      end;
    finally
      op.Free;
    end;
  finally
    if DoDisconnect then begin
      DisconnectInvalidClient(false,errors+' > '+TNetData.HeaderDataToText(HeaderData)+' BuffSize: '+inttostr(DataBuffer.Size));
    end;
  end;
end;

function TNetConnection.DoSendAndWaitForResponse(operation: Word;
  RequestId: Integer; SendDataBuffer, ReceiveDataBuffer: TStream;
  MaxWaitTime: Cardinal; var HeaderData: TNetHeaderData): Boolean;
var tc : TTickCount;
  was_waiting_for_response : Boolean;
  iDebugStep : Integer;
  reservedResponse : TMemoryStream;
begin
  iDebugStep := 0;
  Try
    Result := false;
    HeaderData := CT_NetHeaderData;
    If FIsWaitingForResponse then begin
      TLog.NewLog(ltdebug,Classname,'Is waiting for response ...');
      exit;
    end;
    iDebugStep := 100;
    If Not Assigned(FTcpIpClient) then exit;
    if Not Client.Connected then exit;
    iDebugStep := 110;
    tc := TPlatform.GetTickCount;
    If TPCThread.TryProtectEnterCriticalSection(Self,MaxWaitTime,FNetLock) then begin
      Try
        iDebugStep := 120;
        was_waiting_for_response := RequestId>0;
        try
          if was_waiting_for_response then begin
            iDebugStep := 200;
            FIsWaitingForResponse := true;
            Send(ntp_request,operation,0,RequestId,SendDataBuffer);
          end;
          iDebugStep := 300;
          Repeat
            iDebugStep := 400;
            if (MaxWaitTime > TPlatform.GetTickCount - tc) then MaxWaitTime := MaxWaitTime - (TPlatform.GetTickCount - tc)
            else MaxWaitTime := 1;
            If (MaxWaitTime>60000) then MaxWaitTime:=60000;
            tc := TPlatform.GetTickCount;
            if (ReadTcpClientBuffer(MaxWaitTime,HeaderData,ReceiveDataBuffer)) then begin
              iDebugStep := 500;
              PascalNetData.NodeServersAddresses.UpdateNetConnection(Self);
              iDebugStep := 800;
              TLog.NewLog(ltDebug,Classname,'Received '+CT_NetTransferType[HeaderData.header_type]+' operation:'+TNetData.OperationToText(HeaderData.operation)+' id:'+Inttostr(HeaderData.request_id)+' Buffer size:'+Inttostr(HeaderData.buffer_data_length) );
              if (RequestId=HeaderData.request_id) And (HeaderData.header_type=ntp_response) then begin
                Result := true;
              end else begin
                iDebugStep := 1000;
                case HeaderData.operation of
                  CT_NetOp_Hello : Begin
                    iDebugStep := 1100;
                    DoProcess_Hello(HeaderData,ReceiveDataBuffer);
                  End;
                  CT_NetOp_Message : Begin
                    DoProcess_Message(HeaderData,ReceiveDataBuffer);
                  End;
                  CT_NetOp_GetBlocks : Begin
                    if HeaderData.header_type=ntp_request then
                      DoProcess_GetBlocks_Request(HeaderData,ReceiveDataBuffer)
                    else if HeaderData.header_type=ntp_response then
                      DoProcess_GetBlocks_Response(HeaderData,ReceiveDataBuffer)
                    else DisconnectInvalidClient(false,'Not resquest or response: '+TNetData.HeaderDataToText(HeaderData));
                  End;
                  CT_NetOp_GetBlockHeaders : Begin
                    if HeaderData.header_type=ntp_request then
                      DoProcess_GetOperationsBlock_Request(HeaderData,ReceiveDataBuffer)
                    else TLog.NewLog(ltdebug,Classname,'Received old response of: '+TNetData.HeaderDataToText(HeaderData));
                  End;
                  CT_NetOp_NewBlock : Begin
                    DoProcess_NewBlock(HeaderData,ReceiveDataBuffer);
                  End;
                  CT_NetOp_AddOperations : Begin
                    DoProcess_AddOperations(HeaderData,ReceiveDataBuffer);
                  End;
                  CT_NetOp_GetSafeBox : Begin
                    if HeaderData.header_type=ntp_request then
                      DoProcess_GetSafeBox_Request(HeaderData,ReceiveDataBuffer)
                    else DisconnectInvalidClient(false,'Received '+TNetData.HeaderDataToText(HeaderData));
                  end;
                  CT_NetOp_GetPendingOperations : Begin
                    if (HeaderData.header_type=ntp_request) then
                      DoProcess_GetPendingOperations_Request(HeaderData,ReceiveDataBuffer)
                    else TLog.NewLog(ltdebug,Classname,'Received old response of: '+TNetData.HeaderDataToText(HeaderData));
                  end;
                  CT_NetOp_GetAccount : Begin
                    if (HeaderData.header_type=ntp_request) then
                      DoProcess_GetAccount_Request(HeaderData,ReceiveDataBuffer)
                    else TLog.NewLog(ltdebug,Classname,'Received old response of: '+TNetData.HeaderDataToText(HeaderData));
                  end;
                  CT_NetOp_Reserved_Start..CT_NetOp_Reserved_End : Begin
                    // This will allow to do nothing if not implemented
                    reservedResponse := TMemoryStream.Create;
                    Try
                      PascalNetData.DoProcessReservedAreaMessage(Self,HeaderData,ReceiveDataBuffer,reservedResponse);
                      if (HeaderData.header_type=ntp_request) then begin
                        if (reservedResponse.Size>0) then begin
                          Send(ntp_response,HeaderData.operation,0,HeaderData.request_id,reservedResponse);
                        end else begin
                          // If is a request, and DoProcessReservedAreaMessage didn't filled reservedResponse, will response with ERRORCODE_NOT_IMPLEMENTED
                          Send(ntp_response,HeaderData.operation, CT_NetOp_ERRORCODE_NOT_IMPLEMENTED ,HeaderData.request_id,Nil);
                        end;
                      end;
                    finally
                      reservedResponse.Free;
                    end;
                  end
                else
                  DisconnectInvalidClient(false,'Invalid operation: '+TNetData.HeaderDataToText(HeaderData));
                end;
              end;
            end else sleep(1);
            iDebugStep := 900;
          Until (Result) Or (TPlatform.GetTickCount>(MaxWaitTime+tc)) Or (Not Connected) Or (FDoFinalizeConnection);
        finally
          if was_waiting_for_response then FIsWaitingForResponse := false;
        end;
        iDebugStep := 990;
      Finally
        FNetLock.Release;
      End;
    end;
  Except
    On E:Exception do begin
      E.Message := E.Message+' DoSendAndWaitForResponse step '+Inttostr(iDebugStep)+' Header.operation:'+Inttostr(HeaderData.operation);
      Raise;
    end;
  End;
end;

procedure TNetConnection.FinalizeConnection;
begin
  If FDoFinalizeConnection then exit;
  TLog.NewLog(ltdebug,ClassName,'Executing FinalizeConnection to '+ClientRemoteAddr);
  FDoFinalizeConnection := true;
end;

function TNetConnection.GetClient: TNetTcpIpClient;
begin
  if Not Assigned(FTcpIpClient) then begin
    TLog.NewLog(ltError,Classname,'TcpIpClient=NIL');
    raise Exception.Create('TcpIpClient=NIL');
  end;
  Result := FTcpIpClient;
end;

function TNetConnection.GetConnected: Boolean;
begin
  Result := Assigned(FTcpIpClient) And (FTcpIpClient.Connected);
end;

function TNetConnection.ReadTcpClientBuffer(MaxWaitMiliseconds: Cardinal; var HeaderData: TNetHeaderData; BufferData: TStream): Boolean;
var
  auxstream : TMemoryStream;
  tc : TTickCount;
  last_bytes_read, t_bytes_read : Int64;
  //
  IsValidHeaderButNeedMoreData : Boolean;
  deletedBytes : Int64;


begin
  t_bytes_read := 0;
  Result := false;
  HeaderData := CT_NetHeaderData;
  BufferData.Size := 0;
  TPCThread.ProtectEnterCriticalSection(Self,FNetLock);
  try
    tc := TPlatform.GetTickCount;
    repeat
      If not Connected then exit;
      if Not Client.Connected then exit;
      last_bytes_read := 0;
      FClientBufferRead.Position := 0;
      Result := TNetData.ExtractHeaderInfo(FClientBufferRead,HeaderData,BufferData,IsValidHeaderButNeedMoreData);
      if Result then begin
        FNetProtocolVersion := HeaderData.protocol;
        // Build 1.0.4 accepts net protocol 1 and 2
        if HeaderData.protocol.protocol_version>CT_NetProtocol_Available then begin
          PascalCoinNode.NotifyNetClientMessage(Nil,'Detected a higher Net protocol version at '+
            ClientRemoteAddr+' (v '+inttostr(HeaderData.protocol.protocol_version)+' '+inttostr(HeaderData.protocol.protocol_available)+') '+
            '... check that your version is Ok! Visit official download website for possible updates: https://sourceforge.net/projects/pascalcoin/');
          DisconnectInvalidClient(false,Format('Invalid Net protocol version found: %d available: %d',[HeaderData.protocol.protocol_version,HeaderData.protocol.protocol_available]));
          Result := false;
          exit;
        end else begin
          if (FNetProtocolVersion.protocol_available>CT_NetProtocol_Available) And (Not FAlertedForNewProtocolAvailable) then begin
            FAlertedForNewProtocolAvailable := true;
            PascalCoinNode.NotifyNetClientMessage(Nil,'Detected a new Net protocol version at '+
              ClientRemoteAddr+' (v '+inttostr(HeaderData.protocol.protocol_version)+' '+inttostr(HeaderData.protocol.protocol_available)+') '+
              '... Visit official download website for possible updates: https://sourceforge.net/projects/pascalcoin/');
          end;
          // Remove data from buffer and save only data not processed (higher than stream.position)
          auxstream := TMemoryStream.Create;
          try
            if FClientBufferRead.Position<FClientBufferRead.Size then begin
              auxstream.CopyFrom(FClientBufferRead,FClientBufferRead.Size-FClientBufferRead.Position);
            end;
            FClientBufferRead.Size := 0;
            FClientBufferRead.CopyFrom(auxstream,0);
          finally
            auxstream.Free;
          end;
        end;
      end else begin
        sleep(1);
        if Not Client.WaitForData(100) then begin
          exit;
        end;

        auxstream := (Client as TBufferedNetTcpIpClient).ReadBufferLock;
        try
          last_bytes_read := auxstream.size;
          if last_bytes_read>0 then begin
            FLastDataReceivedTS := TPlatform.GetTickCount;
            FRandomWaitSecondsSendHello := 90 + Random(60);

            FClientBufferRead.Position := FClientBufferRead.size; // Go to the end
            auxstream.Position := 0;
            FClientBufferRead.CopyFrom(auxstream,last_bytes_read);
            FClientBufferRead.Position := 0;
            auxstream.Size := 0;
            t_bytes_read := t_bytes_read + last_bytes_read;
          end;
        finally
          (Client as TBufferedNetTcpIpClient).ReadBufferUnlock;
        end;
      end;
    until (Result) Or ((TPlatform.GetTickCount > (tc+MaxWaitMiliseconds)) And (last_bytes_read=0));
  finally
    Try
      if (Connected) then begin
        if (Not Result) And (FClientBufferRead.Size>0) And (Not IsValidHeaderButNeedMoreData) then begin
          deletedBytes := FClientBufferRead.Size;
          TLog.NewLog(lterror,ClassName,Format('Deleting %d bytes from TcpClient buffer of %s after max %d miliseconds. Elapsed: %d',
            [deletedBytes, Client.ClientRemoteAddr,MaxWaitMiliseconds,TPlatform.GetTickCount-tc]));
          FClientBufferRead.Size:=0;
          DisconnectInvalidClient(false,'Invalid data received in buffer ('+inttostr(deletedBytes)+' bytes)');
        end else if (IsValidHeaderButNeedMoreData) then begin
          TLog.NewLog(ltDebug,ClassName,Format('Not enough data received - Received %d bytes from TcpClient buffer of %s after max %d miliseconds. Elapsed: %d - HeaderData: %s',
            [FClientBufferRead.Size, Client.ClientRemoteAddr,MaxWaitMiliseconds,TPlatform.GetTickCount-tc,TNetData.HeaderDataToText(HeaderData)]));
        end;
      end;
    Finally
      FNetLock.Release;
    End;
  end;
  if t_bytes_read>0 then begin
    if Not FHasReceivedData then begin
      FHasReceivedData := true;
      if (Self is TNetClient) then
        PascalNetData.IncStatistics(0,0,0,1,t_bytes_read,0)
      else PascalNetData.IncStatistics(0,0,0,0,t_bytes_read,0);
    end else begin
      PascalNetData.IncStatistics(0,0,0,0,t_bytes_read,0);
    end;
  end;
  if (Result) And (HeaderData.header_type=ntp_response) then begin
    PascalNetData.UnRegisterRequest(Self,HeaderData.operation,HeaderData.request_id);
  end;
end;

procedure TNetConnection.Send(NetTranferType: TNetTransferType; operation, errorcode: Word; request_id: Integer; DataBuffer: TStream);
Var l : Cardinal;
   w : Word;
  Buffer : TStream;
  s : AnsiString;
begin
  Buffer := TMemoryStream.Create;
  try
    l := CT_MagicNetIdentification;
    Buffer.Write(l,4);
    case NetTranferType of
      ntp_request: begin
        w := CT_MagicRequest;
        Buffer.Write(w,2);
        Buffer.Write(operation,2);
        w := 0;
        Buffer.Write(w,2);
        Buffer.Write(request_id,4);
      end;
      ntp_response: begin
        w := CT_MagicResponse;
        Buffer.Write(w,2);
        Buffer.Write(operation,2);
        Buffer.Write(errorcode,2);
        Buffer.Write(request_id,4);
      end;
      ntp_autosend: begin
        w := CT_MagicAutoSend;
        Buffer.Write(w,2);
        Buffer.Write(operation,2);
        w := errorcode;
        Buffer.Write(w,2);
        l := 0;
        Buffer.Write(l,4);
      end
    else
      raise Exception.Create('Invalid encoding');
    end;
    l := CT_NetProtocol_Version;
    Buffer.Write(l,2);
    l := CT_NetProtocol_Available;
    Buffer.Write(l,2);
    if Assigned(DataBuffer) then begin
      l := DataBuffer.Size;
      Buffer.Write(l,4);
      DataBuffer.Position := 0;
      Buffer.CopyFrom(DataBuffer,DataBuffer.Size);
      s := '(Data:'+inttostr(DataBuffer.Size)+'b) ';
    end else begin
      l := 0;
      Buffer.Write(l,4);
      s := '';
    end;
    Buffer.Position := 0;
    TPCThread.ProtectEnterCriticalSection(Self,FNetLock);
    Try
      TLog.NewLog(ltDebug,Classname,'Sending: '+CT_NetTransferType[NetTranferType]+' operation:'+
        TNetData.OperationToText(operation)+' id:'+Inttostr(request_id)+' errorcode:'+InttoStr(errorcode)+
        ' Size:'+InttoStr(Buffer.Size)+'b '+s+'to '+
        ClientRemoteAddr);
      (Client as TBufferedNetTcpIpClient).WriteBufferToSend(Buffer);
      FLastDataSendedTS := TPlatform.GetTickCount;
      FRandomWaitSecondsSendHello := 90 + Random(60);
    Finally
      FNetLock.Release;
    End;
    PascalNetData.IncStatistics(0,0,0,0,0,Buffer.Size);
  finally
    Buffer.Free;
  end;
end;

procedure TNetConnection.SendError(NetTranferType: TNetTransferType; operation,
  request_id: Integer; error_code: Integer; error_text: AnsiString);
var buffer : TStream;
begin
  buffer := TMemoryStream.Create;
  Try
    TStreamOp.WriteAnsiString(buffer,error_text);
    Send(NetTranferType,operation,error_code,request_id,buffer);
  Finally
    buffer.Free;
  End;
end;

function TNetConnection.Send_AddOperations(Operations : TOperationsHashTree) : Boolean;
Var data : TMemoryStream;
  c1, request_id : Cardinal;
  i, nOpsToSend : Integer;
  optype : Byte;
begin
  Result := false;
  if Not Connected then exit;
  FNetLock.Acquire;
  try
    nOpsToSend := 0;
    FBufferLock.Acquire;
    Try
      If Assigned(Operations) then begin
        for i := 0 to Operations.OperationsCount - 1 do begin
          if FBufferReceivedOperationsHash.IndexOf(Operations.GetOperation(i).Sha256)<0 then begin
            FBufferReceivedOperationsHash.Add(Operations.GetOperation(i).Sha256);
            If FBufferToSendOperations.IndexOfOperation(Operations.GetOperation(i))<0 then begin
              FBufferToSendOperations.AddOperationToHashTree(Operations.GetOperation(i));
            end;
          end;
        end;
        nOpsToSend := Operations.OperationsCount;
      end;
      if FBufferToSendOperations.OperationsCount>0 then begin
        TLog.NewLog(ltdebug,ClassName,Format('Sending %d Operations to %s (inProc:%d, Received:%d)',[FBufferToSendOperations.OperationsCount,ClientRemoteAddr,nOpsToSend,FBufferReceivedOperationsHash.Count]));
        data := TMemoryStream.Create;
        try
          request_id := PascalNetData.NewRequestId;
          c1 := FBufferToSendOperations.OperationsCount;
          data.Write(c1,4);
          for i := 0 to FBufferToSendOperations.OperationsCount-1 do begin
            optype := FBufferToSendOperations.GetOperation(i).OpType;
            data.Write(optype,1);
            FBufferToSendOperations.GetOperation(i).SaveToNettransfer(data);
          end;
          Send(ntp_autosend,CT_NetOp_AddOperations,0,request_id,data);
          FBufferToSendOperations.ClearHastThree;
        finally
          data.Free;
        end;
      end else TLog.NewLog(ltdebug,ClassName,Format('Not sending any operations to %s (inProc:%d, Received:%d, Sent:%d)',[ClientRemoteAddr,nOpsToSend,FBufferReceivedOperationsHash.Count,FBufferToSendOperations.OperationsCount]));
    finally
      FBufferLock.Release;
    end;
  finally
    FNetLock.Release;
  end;
  Result := Connected;
end;

function TNetConnection.Send_GetBlocks(StartAddress, quantity : Cardinal; var request_id : Cardinal) : Boolean;
Var data : TMemoryStream;
  c1,c2 : Cardinal;
begin
  Result := false;
  request_id := 0;
  if (FRemoteOperationBlock.block<PascalCoinSafeBox.BlocksCount) Or (FRemoteOperationBlock.block=0) then exit;
  if Not Connected then exit;
  // First receive operations from
  data := TMemoryStream.Create;
  try
    if PascalCoinSafeBox.BlocksCount=0 then c1:=0
    else c1:=StartAddress;
    if (quantity=0) then begin
      if FRemoteOperationBlock.block>0 then c2 := FRemoteOperationBlock.block
      else c2 := c1+100;
    end else c2 := c1+quantity-1;
    // Build 1.0.5 BUG - Always query for ONLY 1 if Build is lower or equal to 1.0.5
    if ((FClientAppVersion='') Or ( (length(FClientAppVersion)=5) And (FClientAppVersion<='1.0.5') )) then begin
      c2 := c1;
    end;
    data.Write(c1,4);
    data.Write(c2,4);
    request_id := PascalNetData.NewRequestId;
    PascalNetData.RegisterRequest(Self,CT_NetOp_GetBlocks,request_id);
    TLog.NewLog(ltdebug,ClassName,Format('Send GET BLOCKS start:%d quantity:%d (from:%d to %d)',[StartAddress,quantity,StartAddress,quantity+StartAddress]));
    FIsDownloadingBlocks := quantity>1;
    Send(ntp_request,CT_NetOp_GetBlocks,0,request_id,data);
    Result := Connected;
  finally
    data.Free;
  end;
end;

function TNetConnection.Send_Hello(NetTranferType : TNetTransferType; request_id : Integer) : Boolean;
  { HELLO command:
    - Operation stream
    - My Active server port (0 if no active). (2 bytes)
    - A Random Longint (4 bytes) to check if its myself connection to my server socket
    - My Unix Timestamp (4 bytes)
    - Registered node servers count
      (For each)
      - ip (string)
      - port (2 bytes)
      - last_connection UTS (4 bytes)
    - My Server port (2 bytes)
    - If this is a response:
      - If remote operation block is lower than me:
        - Send My Operation Stream in the same block thant requester
      }
var data : TStream;
  i : Integer;
  nsa : TNodeServerAddress;
  nsarr : TNodeServerAddressArray;
  w : Word;
  currunixtimestamp : Cardinal;
begin
  Result := false;
  if Not Connected then exit;
  // Send Hello command:
  data := TMemoryStream.Create;
  try
    if NetTranferType=ntp_request then begin
      PascalNetData.RegisterRequest(Self,CT_NetOp_Hello,request_id);
    end;
    If PascalCoinNode.NetServer.Active then
      w := PascalCoinNode.NetServer.Port
    else w := 0;
    // Save active server port (2 bytes). 0 = No active server port
    data.Write(w,2);
    // Save My connection public key
    TStreamOp.WriteAnsiString(data,TAccountComp.AccountKey2RawString(PascalNetData.NodePrivateKey.PublicKey));
    // Save my Unix timestamp (4 bytes)
    currunixtimestamp := UnivDateTimeToUnix(DateTime2UnivDateTime(now));
    data.Write(currunixtimestamp,4);
    // Save last operations block
    TPCOperationsComp.SaveOperationBlockToStream(PascalCoinBank.LastOperationBlock,data);
    nsarr := PascalNetData.NodeServersAddresses.GetValidNodeServers(true,CT_MAX_NODESERVERS_ON_HELLO);
    i := length(nsarr);
    data.Write(i,4);
    for i := 0 to High(nsarr) do begin
      nsa := nsarr[i];
      TStreamOp.WriteAnsiString(data, nsa.ip);
      data.Write(nsa.port,2);
      data.Write(nsa.last_connection,4);
    end;
    // Send client version
    TStreamOp.WriteAnsiString(data,CT_ClientAppVersion{$IFDEF LINUX}+'l'{$ELSE}+'w'{$ENDIF}{$IFDEF FPC}{$IFDEF LCL}+'L'{$ELSE}+'F'{$ENDIF}{$ENDIF});
    // Build 1.5 send accumulated work
    data.Write(PascalCoinSafeBox.WorkSum,SizeOf(PascalCoinSafeBox.WorkSum));
    //
    Send(NetTranferType,CT_NetOp_Hello,0,request_id,data);
    Result := Client.Connected;
  finally
    data.Free;
  end;
end;

function TNetConnection.Send_Message(const TheMessage: AnsiString): Boolean;
Var data : TStream;
  cyp : TRawBytes;
begin
  Result := false;
  if Not Connected then exit;
  data := TMemoryStream.Create;
  Try
    // Cypher message:
    cyp := ECIESEncrypt(FClientPublicKey,TheMessage);
    TStreamOp.WriteAnsiString(data,cyp);
    Send(ntp_autosend,CT_NetOp_Message,0,0,data);
    Result := true;
  Finally
    data.Free;
  End;
end;

function TNetConnection.Send_NewBlockFound(const NewBlock: TPCOperationsComp
  ): Boolean;
var data : TStream;
  request_id : Integer;
begin
  Result := false;
  if Not Connected then exit;
  FNetLock.Acquire;
  Try
    // Clear buffers
    FBufferLock.Acquire;
    Try
      FBufferReceivedOperationsHash.Clear;
      FBufferToSendOperations.ClearHastThree;
    finally
      FBufferLock.Release;
    end;
    // Checking if operationblock is the same to prevent double messaging...
    If (TPCOperationsComp.EqualsOperationBlock(FRemoteOperationBlock,NewBlock.OperationBlock)) then begin
      TLog.NewLog(ltDebug,ClassName,'This connection has the same block, does not need to send');
      exit;
    end;
    if (PascalCoinSafeBox.BlocksCount<>NewBlock.OperationBlock.block+1) then begin
      TLog.NewLog(ltDebug,ClassName,'The block number '+IntToStr(NewBlock.OperationBlock.block)+' is not equal to current blocks stored in bank ('+IntToStr(PascalCoinSafeBox.BlocksCount)+'), finalizing');
      exit;
    end;
    data := TMemoryStream.Create;
    try
      request_id := PascalNetData.NewRequestId;
      NewBlock.SaveBlockToStream(false,data);
      data.Write(PascalCoinSafeBox.WorkSum,SizeOf(PascalCoinSafeBox.WorkSum));
      Send(ntp_autosend,CT_NetOp_NewBlock,0,request_id,data);
    finally
      data.Free;
    end;
  Finally
    FNetLock.Release;
  End;
  Result := Connected;
end;

// *** Skybuck: CHECK THIS LATER IF THIS METHOD STILL NECESSARY or can be removed ***
procedure TNetConnection.SetClient(const Value: TNetTcpIpClient);
Var old : TNetTcpIpClient;
begin
  if FTcpIpClient<>Value then begin
    if Assigned(FTcpIpClient) then begin
      FTcpIpClient.OnConnect := Nil;
      FTcpIpClient.OnDisconnect := Nil;
//      FTcpIpClient.RemoveFreeNotification(Self);
    end;
    PascalNetData.UnRegisterRequest(Self,0,0);
    old := FTcpIpClient;
    FTcpIpClient := Value;
    if Assigned(old) then begin
//      if old.Owner=Self then begin
        old.Free;
//      end;
    end;
  end;
  if Assigned(FTcpIpClient) then begin
//    FTcpIpClient.FreeNotification(Self);
    FTcpIpClient.OnConnect := TcpClient_OnConnect;
    FTcpIpClient.OnDisconnect := TcpClient_OnDisconnect;
  end;
  PascalNetData.NotifyNetConnectionUpdated;
end;

procedure TNetConnection.SetConnected(const Value: Boolean);
begin
  if (Value = GetConnected) then exit;
  if Value then ConnectTo(Client.RemoteHost,Client.RemotePort)
  else begin
    FinalizeConnection;
    Client.Disconnect;
  end;
end;

procedure TNetConnection.TcpClient_OnConnect(Sender: TObject);
begin
  PascalNetData.IncStatistics(1,0,1,0,0,0);
  TLog.NewLog(ltInfo,Classname,'Connected to a server '+ClientRemoteAddr);
  PascalNetData.NotifyNetConnectionUpdated;
end;

procedure TNetConnection.TcpClient_OnDisconnect(Sender: TObject);
begin
  if self is TNetServerClient then PascalNetData.IncStatistics(-1,-1,0,0,0,0)
  else begin
    if FHasReceivedData then PascalNetData.IncStatistics(-1,0,-1,-1,0,0)
    else PascalNetData.IncStatistics(-1,0,-1,0,0,0);
  end;
  TLog.NewLog(ltInfo,Classname,'Disconnected from '+ClientRemoteAddr);
  PascalNetData.NotifyNetConnectionUpdated;
  if (FClientTimestampIp<>'') then begin
    PascalNetData.NetworkAdjustedTime.RemoveIp(FClientTimestampIp);
  end;
end;

end.

