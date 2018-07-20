unit UOperationsHashTree;

interface

uses
  Classes, UThread, URawBytes, UPCOperation, UAccountPreviousBlockInfo;

type
  { TOperationsHashTree }
  TOperationsHashTree = Class
  private
    FListOrderedByAccountsData : TList;
    FListOrderedBySha256 : TList; // Improvement TOperationsHashTree speed 2.1.6
    FHashTreeOperations : TPCThreadList; // Improvement TOperationsHashTree speed 2.1.6
    FHashTree: TRawBytes;
    FOnChanged: TNotifyEvent;
    FTotalAmount : Int64;
    FTotalFee : Int64;
    Procedure InternalAddOperationToHashTree(list : TList; op : TPCOperation; CalcNewHashTree : Boolean);
    Function FindOrderedBySha(lockedThreadList : TList; const Value: TRawBytes; var Index: Integer): Boolean;
    Function FindOrderedByAccountData(lockedThreadList : TList; const account_number : Cardinal; var Index: Integer): Boolean;
    function GetHashTree: TRawBytes;
  public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure AddOperationToHashTree(op : TPCOperation);
    Procedure ClearHastThree;
    Property HashTree : TRawBytes read GetHashTree;
    Function OperationsCount : Integer;
    Function GetOperation(index : Integer) : TPCOperation;
    Function GetOperationsAffectingAccount(account_number : Cardinal; List : TList) : Integer;
    Procedure CopyFromHashTree(Sender : TOperationsHashTree);
    Property TotalAmount : Int64 read FTotalAmount;
    Property TotalFee : Int64 read FTotalFee;
    function SaveOperationsHashTreeToStream(Stream: TStream; SaveToStorage : Boolean): Boolean;
    function LoadOperationsHashTreeFromStream(Stream: TStream; LoadingFromStorage : Boolean; LoadProtocolVersion : Word; PreviousUpdatedBlocks : TAccountPreviousBlockInfo; var errors : AnsiString): Boolean;
    function IndexOfOperation(op : TPCOperation) : Integer;
    function CountOperationsBySameSignerWithoutFee(account_number : Cardinal) : Integer;
    Procedure Delete(index : Integer);
    Property OnChanged : TNotifyEvent read FOnChanged write FOnChanged;
  End;

implementation

uses
  ULog, UConst, UPtrInt, SysUtils, UCrypto, UBaseType, UPCOperationClass, UPCOperationsComp;

{ TOperationsHashTree }

Type TOperationHashTreeReg = Record
       Op : TPCOperation;
     end;
     POperationHashTreeReg = ^TOperationHashTreeReg;
     TOperationsHashAccountsData = Record
       account_number : Cardinal;
       account_count : Integer;
       account_without_fee : Integer;
     end;
     POperationsHashAccountsData = ^TOperationsHashAccountsData;

procedure TOperationsHashTree.AddOperationToHashTree(op: TPCOperation);
Var l : TList;
begin
  l := FHashTreeOperations.LockList;
  try
    InternalAddOperationToHashTree(l,op,True);
  finally
    FHashTreeOperations.UnlockList;
  end;
end;

procedure TOperationsHashTree.ClearHastThree;
var l : TList;
  i : Integer;
  P : POperationHashTreeReg;
  PaccData : POperationsHashAccountsData;
begin
  l := FHashTreeOperations.LockList;
  try
    FTotalAmount := 0;
    FTotalFee := 0;
    Try
      for i := 0 to l.Count - 1 do begin
        P := l[i];
        P^.Op.Free;
        Dispose(P);
      end;
      for i:=0 to FListOrderedByAccountsData.Count-1 do begin
        PaccData := FListOrderedByAccountsData[i];
        Dispose(PaccData);
      end;
    Finally
      l.Clear;
      FListOrderedBySha256.Clear;
      FListOrderedByAccountsData.Clear;
      FHashTree := '';
    End;
    If Assigned(FOnChanged) then FOnChanged(Self);
  finally
    FHashTreeOperations.UnlockList;
  end;
end;

procedure TOperationsHashTree.CopyFromHashTree(Sender: TOperationsHashTree);
Var i : Integer;
  lme, lsender : TList;
  PSender : POperationHashTreeReg;
  lastNE : TNotifyEvent;
begin
  if (Sender = Self) then begin
    exit;
  end;
  lme := FHashTreeOperations.LockList;
  try
    lastNE := FOnChanged;
    FOnChanged := Nil;
    try
      ClearHastThree;
      lsender := Sender.FHashTreeOperations.LockList;
      try
        for i := 0 to lsender.Count - 1 do begin
          PSender := lsender[i];
          InternalAddOperationToHashTree(lme,PSender^.Op,False);
        end;
        // Improvement TOperationsHashTree speed 2.1.6
        // FHashTree value updated now, not on every for cycle
        FHashTree:=Sender.FHashTree;
      finally
        Sender.FHashTreeOperations.UnlockList;
      end;
    finally
      FOnChanged := lastNE;
    end;
    If Assigned(FOnChanged) then FOnChanged(Self);
  finally
    FHashTreeOperations.UnlockList;
  end;
end;

constructor TOperationsHashTree.Create;
begin
  FOnChanged:=Nil;
  FListOrderedBySha256 := TList.Create;
  FListOrderedByAccountsData := TList.Create;
  FTotalAmount := 0;
  FTotalFee := 0;
  FHashTree := '';
  FHashTreeOperations := TPCThreadList.Create('TOperationsHashTree_HashTreeOperations');
end;

procedure TOperationsHashTree.Delete(index: Integer);
Var l : TList;
  P : POperationHashTreeReg;
  i,iDel,iValuePosDeleted : Integer;
  PaccData : POperationsHashAccountsData;
begin
  l := FHashTreeOperations.LockList;
  try
    P := l[index];

    // Delete from Ordered
    If Not FindOrderedBySha(l,P^.Op.Sha256,iDel) then begin
      TLog.NewLog(ltError,ClassName,'DEV ERROR 20180213-1 Operation not found in ordered list: '+P^.Op.ToString);
    end else begin
      iValuePosDeleted := PtrInt(FListOrderedBySha256[iDel]);
      FListOrderedBySha256.Delete(iDel);
      // Decrease values > iValuePosDeleted
      for i := 0 to FListOrderedBySha256.Count - 1 do begin
        if PtrInt(FListOrderedBySha256[i])>iValuePosDeleted then begin
          FListOrderedBySha256[i] := TObject( PtrInt(FListOrderedBySha256[i]) - 1 );
        end;
      end;
    end;
    // Delete from account Data
    If Not FindOrderedByAccountData(l,P^.Op.SignerAccount,i) then begin
      TLog.NewLog(ltError,ClassName,Format('DEV ERROR 20180213-3 account %d not found in ordered list: %s',[P^.Op.SignerAccount,P^.Op.ToString]));
    end else begin
      PaccData := POperationsHashAccountsData( FListOrderedByAccountsData[i] );
      Dec(PaccData.account_count);
      If (P^.Op.OperationFee=0) then Dec(PaccData.account_without_fee);
      If (PaccData.account_count<=0) then begin
        Dispose(PaccData);
        FListOrderedByAccountsData.Delete(i);
      end;
    end;

    l.Delete(index);
    P^.Op.Free;
    Dispose(P);
    // Recalc operations hash
    FTotalAmount := 0;
    FTotalFee := 0;
    FHashTree := ''; // Init to future recalc
    for i := 0 to l.Count - 1 do begin
      P := l[i];
      // Include to hash tree
      P^.Op.tag := i;
     FTotalAmount := FTotalAmount + P^.Op.OperationAmount;
      FTotalFee := FTotalFee + P^.Op.OperationFee;
    end;
    If Assigned(FOnChanged) then FOnChanged(Self);
  finally
    FHashTreeOperations.UnlockList;
  end;
end;

destructor TOperationsHashTree.Destroy;
begin
  FOnChanged := Nil;
  ClearHastThree;
  FreeAndNil(FHashTreeOperations);
  SetLength(FHashTree,0);
  FreeAndNil(FListOrderedBySha256);
  FreeAndNil(FListOrderedByAccountsData);
  inherited;
end;

function TOperationsHashTree.GetHashTree: TRawBytes;
Var l : TList;
  i : Integer;
  P : POperationHashTreeReg;
begin
  if Length(FHashTree)<>32 then begin
    l := FHashTreeOperations.LockList;
    Try
      TCrypto.DoSha256('',FHashTree);
      for i := 0 to l.Count - 1 do begin
        P := l[i];
        // Include to hash tree
        // TCrypto.DoSha256(FHashTree+P^.Op.Sha256,FHashTree);  COMPILER BUG 2.1.6: Using FHashTree as a "out" param can be initialized prior to be updated first parameter!
        FHashTree := TCrypto.DoSha256(FHashTree+P^.Op.Sha256);
      end;
    Finally
      FHashTreeOperations.UnlockList;
    End;
  end;
  Result := FHashTree;
end;

function TOperationsHashTree.GetOperation(index: Integer): TPCOperation;
Var l : TList;
begin
  l := FHashTreeOperations.LockList;
  try
    Result := POperationHashTreeReg(l[index])^.Op;
  finally
    FHashTreeOperations.UnlockList;
  end;
end;

function TOperationsHashTree.GetOperationsAffectingAccount(account_number: Cardinal; List: TList): Integer;
  // This function retrieves operations from HashTree that affeccts to an account_number
Var l,intl : TList;
  i,j : Integer;
begin
  List.Clear;
  l := FHashTreeOperations.LockList;
  try
    intl := TList.Create;
    try
      for i := 0 to l.Count - 1 do begin
        intl.Clear;
        POperationHashTreeReg(l[i])^.Op.AffectedAccounts(intl);
        if intl.IndexOf(TObject(account_number))>=0 then List.Add(TObject(i));
      end;
    finally
      intl.Free;
    end;
    Result := List.Count;
  finally
    FHashTreeOperations.UnlockList;
  end;
end;

function TOperationsHashTree.IndexOfOperation(op: TPCOperation): Integer;
Var iPosInOrdered : Integer;
  l : TList;
  OpSha256 : TRawBytes;
begin
  OpSha256 := op.Sha256;
  l := FHashTreeOperations.LockList;
  Try
    // Improvement TOperationsHashTree speed 2.1.5.1
    // Use ordered search
    If FindOrderedBySha(l,OpSha256,iPosInOrdered) then begin
      Result := PtrInt(FListOrderedBySha256.Items[iPosInOrdered]);
    end else Result := -1;
  Finally
    FHashTreeOperations.UnlockList;
  End;
end;

function TOperationsHashTree.CountOperationsBySameSignerWithoutFee(account_number: Cardinal): Integer;
Var l : TList;
  i : Integer;
begin
  Result := 0;
  l := FHashTreeOperations.LockList;
  Try
    // Improvement TOperationsHashTree speed 2.1.5.1
    // Use ordered accounts Data search
    If FindOrderedByAccountData(l,account_number,i) then begin
      Result := POperationsHashAccountsData(FListOrderedByAccountsData[i])^.account_without_fee;
    end else Result := 0;
  Finally
    FHashTreeOperations.UnlockList;
  End;
end;

procedure TOperationsHashTree.InternalAddOperationToHashTree(list: TList; op: TPCOperation; CalcNewHashTree : Boolean);
Var msCopy : TMemoryStream;
  h : TRawBytes;
  P : POperationHashTreeReg;
  PaccData : POperationsHashAccountsData;
  i,npos,iListSigners : Integer;
  listSigners : TList;
begin
  msCopy := TMemoryStream.Create;
  try
    New(P);
    P^.Op := TPCOperation( op.NewInstance );
    P^.Op.InitializeData;
    op.SaveOpToStream(msCopy,true);
    msCopy.Position := 0;
    P^.Op.LoadOpFromStream(msCopy, true);
    // Skybuck: modified to use write properties
    P^.Op.Previous_Signer_updated_block := op.Previous_Signer_updated_block;
    P^.Op.Previous_Destination_updated_block := op.Previous_Destination_updated_block;
    P^.Op.Previous_Seller_updated_block := op.Previous_Seller_updated_block;
    h := FHashTree + op.Sha256;
    P^.Op.BufferedSha256:=op.BufferedSha256;
    P^.Op.tag := list.Count;
    // Improvement TOperationsHashTree speed 2.1.6
    // Include to hash tree (Only if CalcNewHashTree=True)
    If (CalcNewHashTree) And (Length(FHashTree)=32) then begin
      // TCrypto.DoSha256(FHashTree+op.Sha256,FHashTree);  COMPILER BUG 2.1.6: Using FHashTree as a "out" param can be initialized prior to be updated first parameter!
      TCrypto.DoSha256(h,FHashTree);
    end;
    npos := list.Add(P);
    // Improvement: Will allow to add duplicate Operations, so add only first to orderedBySha
    If Not FindOrderedBySha(list,op.Sha256,i) then begin
      // Protection: Will add only once
      FListOrderedBySha256.Insert(i,TObject(npos));
    end;
    // Improvement TOperationsHashTree speed 2.1.6
    // Mantain an ordered Accounts list with data
    listSigners := TList.Create;
    try
      op.SignerAccounts(listSigners);
      for iListSigners:=0 to listSigners.Count-1 do begin
        If Not FindOrderedByAccountData(list,PtrInt(listSigners[iListSigners]),i) then begin
          New(PaccData);
          PaccData^.account_number:=PtrInt(listSigners[iListSigners]);
          PaccData^.account_count:=0;
          PaccData^.account_without_fee:=0;
          FListOrderedByAccountsData.Insert(i,PaccData);
        end else PaccData := FListOrderedByAccountsData[i];
        Inc(PaccData^.account_count);
        If op.OperationFee=0 then begin
          Inc(PaccData^.account_without_fee);
        end;
      end;
    finally
      listSigners.Free;
    end;
  finally
    msCopy.Free;
  end;
  FTotalAmount := FTotalAmount + op.OperationAmount;
  FTotalFee := FTotalFee + op.OperationFee;
  If Assigned(FOnChanged) then FOnChanged(Self);
end;

function TOperationsHashTree.FindOrderedBySha(lockedThreadList : TList; const Value: TRawBytes; var Index: Integer): Boolean;
var L, H, I : Integer;
  iLockedThreadListPos : PtrInt;
  C : Int64;
  P : POperationHashTreeReg;
begin
  Result := False;
  L := 0;
  H := FListOrderedBySha256.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    iLockedThreadListPos := PtrInt(FListOrderedBySha256[I]);
    C := TBaseType.BinStrComp(POperationHashTreeReg(lockedThreadList[iLockedThreadListPos])^.Op.Sha256,Value);
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

function TOperationsHashTree.FindOrderedByAccountData(lockedThreadList: TList; const account_number: Cardinal; var Index: Integer): Boolean;
var L, H, I : Integer;
  C : Int64;
begin
  Result := False;
  L := 0;
  H := FListOrderedByAccountsData.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := Int64(POperationsHashAccountsData(FListOrderedByAccountsData[I])^.account_number) - Int64(account_number);
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

function TOperationsHashTree.LoadOperationsHashTreeFromStream(Stream: TStream; LoadingFromStorage : Boolean; LoadProtocolVersion : Word; PreviousUpdatedBlocks : TAccountPreviousBlockInfo; var errors: AnsiString): Boolean;
Var c, i: Cardinal;
  OpType: Cardinal;
  bcop: TPCOperation;
  j: Integer;
  OpClass: TPCOperationClass;
  lastNE : TNotifyEvent;
begin
  Result := false;
  //
  If Stream.Read(c, 4)<4 then begin
    errors := 'Cannot read operations count';
    exit;
  end;
  lastNE := FOnChanged;
  FOnChanged:=Nil;
  try
    // c = operations count
    for i := 1 to c do begin
      if Stream.Size - Stream.Position < 4 then begin
        errors := 'Invalid operation structure ' + inttostr(i) + '/' + inttostr(c);
        exit;
      end;
      Stream.Read(OpType, 4);
      j := TPCOperationsComp.IndexOfOperationClassByOpType(OpType);
      if j >= 0 then
        OpClass := _OperationsClass[j]
      else
        OpClass := Nil;
      if Not Assigned(OpClass) then begin
        errors := 'Invalid operation structure ' + inttostr(i) + '/' + inttostr(c) + ' optype not valid:' + InttoHex(OpType, 4);
        exit;
      end;
      bcop := OpClass.Create;
      Try
        if LoadingFromStorage then begin
          If not bcop.LoadFromStorage(Stream,LoadProtocolVersion,PreviousUpdatedBlocks) then begin
            errors := 'Invalid operation load from storage ' + inttostr(i) + '/' + inttostr(c)+' Class:'+OpClass.ClassName;
            exit;
          end;
        end else if not bcop.LoadFromNettransfer(Stream) then begin
          errors := 'Invalid operation load from stream ' + inttostr(i) + '/' + inttostr(c)+' Class:'+OpClass.ClassName;
          exit;
        end;
        AddOperationToHashTree(bcop);
      Finally
        FreeAndNil(bcop);
      end;
    end;
  finally
    FOnChanged := lastNE;
  end;
  If Assigned(FOnChanged) then FOnChanged(Self);
  errors := '';
  Result := true;
end;

function TOperationsHashTree.OperationsCount: Integer;
Var l : TList;
begin
  l := FHashTreeOperations.LockList;
  try
    Result := l.Count;
  finally
    FHashTreeOperations.UnlockList;
  end;
end;

function TOperationsHashTree.SaveOperationsHashTreeToStream(Stream: TStream; SaveToStorage: Boolean): Boolean;
Var c, i, OpType: Cardinal;
  bcop: TPCOperation;
  l : TList;
begin
  l := FHashTreeOperations.LockList;
  Try
    c := l.Count;
    Stream.Write(c, 4);
    // c = operations count
    for i := 1 to c do begin
      bcop := GetOperation(i - 1);
      OpType := bcop.OpType;
      Stream.write(OpType, 4);
      if SaveToStorage then bcop.SaveToStorage(Stream)
      else bcop.SaveToNettransfer(Stream);
    end;
    Result := true;
  Finally
    FHashTreeOperations.UnlockList;
  End;
end;


end.
