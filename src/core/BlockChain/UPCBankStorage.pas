unit UPCBankStorage;

interface

uses
  UStorage, UPCBank;

type
  TPCBankStorage = class
  private
    FStorage : TStorage;
    FStorageClass: TStorageClass;

    FBank : TPCBank;

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    procedure SetBank(const Value: TPCBank);
    {$ENDIF}

    function GetStorage: TStorage;
    procedure SetStorageClass(const Value: TStorageClass);
  protected

    Function DoSaveBank : Boolean; virtual; abstract;
    Function DoRestoreBank(max_block : Int64) : Boolean; virtual; abstract;

  public

    Function SaveBank : Boolean;
    Function RestoreBank(max_block : Int64) : Boolean;

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    Property Bank : TPCBank read FBank write SetBank;
    {$ENDIF}

    Property Storage : TStorage read GetStorage;
    Property StorageClass : TStorageClass read FStorageClass write SetStorageClass;

  end;

implementation

function TPCBank.GetStorage: TStorage;
begin
  if Not Assigned(FStorage) then begin
    if Not Assigned(FStorageClass) then raise Exception.Create('StorageClass not defined');
    FStorage := FStorageClass.Create(Self);

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    FStorage.Bank := Self;
    {$ENDIF}
  end;
  Result := FStorage;
end;


function TStorage.SaveBank: Boolean;
begin
  Result := true;
  If FIsMovingBlockchain then Exit;
  {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
  if Not TPCSafeBox.MustSafeBoxBeSaved(Bank.BlocksCount) then exit; // No save
  Try
    Result := DoSaveBank;
    FBank.SafeBox.CheckMemory;
  Except
    On E:Exception do begin
      TLog.NewLog(lterror,Classname,'Error saving Bank: '+E.Message);
      Raise;
    end;
  End;
  {$ENDIF}
end;

{$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
procedure TStorage.SetBank(const Value: TPCBank);
begin
  FBank := Value;
end;
{$ENDIF}

function TStorage.RestoreBank(max_block: Int64): Boolean;
begin
  Result := DoRestoreBank(max_block);
end;

procedure TPCBank.SetStorageClass(const Value: TStorageClass);
begin
  if FStorageClass=Value then exit;
  FStorageClass := Value;
  if Assigned(FStorage) then FreeAndNil(FStorage);
end;



end.
