unit UStorage;

interface

uses
  Classes, UOrphan, UPCOperationsComp, UOperationsHashTree;

type
  { TStorage }
  TStorage = Class
  private
    FOrphan: TOrphan;

    FReadOnly: Boolean;
  protected
    FIsMovingBlockchain : Boolean;
    procedure SetOrphan(const Value: TOrphan); virtual;
    procedure SetReadOnly(const Value: Boolean); virtual;
    Function DoLoadBlockChain(Operations : TPCOperationsComp; Block : Cardinal) : Boolean; virtual; abstract;
    Function DoSaveBlockChain(Operations : TPCOperationsComp) : Boolean; virtual; abstract;
    Function DoMoveBlockChain(StartBlock : Cardinal; Const DestOrphan : TOrphan; DestStorage : TStorage) : Boolean; virtual; abstract;
    Function DoSaveBank : Boolean; virtual; abstract;
    Function DoRestoreBank(max_block : Int64) : Boolean; virtual; abstract;
    Procedure DoDeleteBlockChainBlocks(StartingDeleteBlock : Cardinal); virtual; abstract;
    function GetFirstBlockNumber: Int64; virtual; abstract;
    function GetLastBlockNumber: Int64; virtual; abstract;
    function DoInitialize:Boolean; virtual; abstract;
    Function DoCreateSafeBoxStream(blockCount : Cardinal) : TStream; virtual; abstract;
    Procedure DoEraseStorage; virtual; abstract;
    Procedure DoSavePendingBufferOperations(OperationsHashTree : TOperationsHashTree); virtual; abstract;
    Procedure DoLoadPendingBufferOperations(OperationsHashTree : TOperationsHashTree); virtual; abstract;
  public
    // Skybuck: moved to here so TPCBank can access it
    Function BlockExists(Block : Cardinal) : Boolean; virtual; abstract;

    Function LoadBlockChainBlock(Operations : TPCOperationsComp; Block : Cardinal) : Boolean;
    Function SaveBlockChainBlock(Operations : TPCOperationsComp) : Boolean;
    Function MoveBlockChainBlocks(StartBlock : Cardinal; Const DestOrphan : TOrphan; DestStorage : TStorage) : Boolean;
    Procedure DeleteBlockChainBlocks(StartingDeleteBlock : Cardinal);
    Function SaveBank : Boolean;
    Function RestoreBank(max_block : Int64) : Boolean;
    Constructor Create;
    Property Orphan : TOrphan read FOrphan write SetOrphan;
    Property ReadOnly : Boolean read FReadOnly write SetReadOnly;
    Procedure CopyConfiguration(Const CopyFrom : TStorage); virtual;
    Property FirstBlock : Int64 read GetFirstBlockNumber;
    Property LastBlock : Int64 read GetLastBlockNumber;
    Function Initialize : Boolean;
    Function CreateSafeBoxStream(blockCount : Cardinal) : TStream;
    Function HasUpgradedToVersion2 : Boolean; virtual; abstract;
    Procedure CleanupVersion1Data; virtual; abstract;
    Procedure EraseStorage;
    Procedure SavePendingBufferOperations(OperationsHashTree : TOperationsHashTree);
    Procedure LoadPendingBufferOperations(OperationsHashTree : TOperationsHashTree);
  End;

implementation

uses
  SysUtils, ULog, UPascalCoinBank, UPascalCoinSafeBox;

{ TStorage }

procedure TStorage.CopyConfiguration(const CopyFrom: TStorage);
begin
  Orphan := CopyFrom.Orphan;
end;

constructor TStorage.Create;
begin
  inherited;
  FOrphan := '';
  FReadOnly := false;
  FIsMovingBlockchain := False;
end;

procedure TStorage.DeleteBlockChainBlocks(StartingDeleteBlock: Cardinal);
begin
  if ReadOnly then raise Exception.Create('Cannot delete blocks because is ReadOnly');
  DoDeleteBlockChainBlocks(StartingDeleteBlock);
end;

function TStorage.Initialize: Boolean;
begin
  Result := DoInitialize;
end;

function TStorage.CreateSafeBoxStream(blockCount: Cardinal): TStream;
begin
  Result := DoCreateSafeBoxStream(blockCount);
end;

procedure TStorage.EraseStorage;
begin
  TLog.NewLog(ltInfo,ClassName,'Executing EraseStorage');
  DoEraseStorage;
end;

procedure TStorage.SavePendingBufferOperations(OperationsHashTree : TOperationsHashTree);
begin
  DoSavePendingBufferOperations(OperationsHashTree);
end;

procedure TStorage.LoadPendingBufferOperations(OperationsHashTree : TOperationsHashTree);
begin
  DoLoadPendingBufferOperations(OperationsHashTree);
end;

function TStorage.LoadBlockChainBlock(Operations: TPCOperationsComp; Block: Cardinal): Boolean;
begin
  if (Block<FirstBlock) Or (Block>LastBlock) then result := false
  else Result := DoLoadBlockChain(Operations,Block);
end;

function TStorage.MoveBlockChainBlocks(StartBlock: Cardinal; const DestOrphan: TOrphan; DestStorage : TStorage): Boolean;
begin
  if Assigned(DestStorage) then begin
    if DestStorage.ReadOnly then raise Exception.Create('Cannot move blocks because is ReadOnly');
  end else if ReadOnly then raise Exception.Create('Cannot move blocks from myself because is ReadOnly');
  Result := DoMoveBlockChain(StartBlock,DestOrphan,DestStorage);
end;

function TStorage.RestoreBank(max_block: Int64): Boolean;
begin
  Result := DoRestoreBank(max_block);
end;

function TStorage.SaveBank: Boolean;
begin
  Result := true;
  If FIsMovingBlockchain then Exit;
  if Not TPCSafeBox.MustSafeBoxBeSaved(PascalCoinSafeBox.BlocksCount) then exit; // No save
  Try
    Result := DoSaveBank;
    PascalCoinSafeBox.CheckMemory;
  Except
    On E:Exception do begin
      TLog.NewLog(lterror,Classname,'Error saving Bank: '+E.Message);
      Raise;
    end;
  End;
end;

function TStorage.SaveBlockChainBlock(Operations: TPCOperationsComp): Boolean;
begin
  Try
    if ReadOnly then raise Exception.Create('Cannot save because is ReadOnly');
    Result := DoSaveBlockChain(Operations);
  Except
    On E:Exception do begin
      TLog.NewLog(lterror,Classname,'Error saving block chain: '+E.Message);
      Raise;
    end;
  End;
end;

procedure TStorage.SetOrphan(const Value: TOrphan);
begin
  FOrphan := Value;
end;

procedure TStorage.SetReadOnly(const Value: Boolean);
begin
  FReadOnly := Value;
end;

end.
