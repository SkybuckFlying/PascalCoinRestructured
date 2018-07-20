unit UMemAccount;

interface

uses
  UAccountInfoKS, UDynRawBytes, URawBytes, UAccount;

{$include MemoryReductionSettings.inc}

type
{$IFDEF uselowmem}
  { In order to store less memory on RAM, those types will be used
    to store in RAM memory (better than to use original ones)
    This will reduce 10-15% of memory usage.
    For future versions, will be a good solution to use those instead
    of originals, but}
  TMemAccount = Record // TAccount with less memory usage
    // account number is discarded (-4 bytes)
    {$IFDEF useAccountKeyStorage}
    accountInfoKS : TAccountInfoKS;
    {$ELSE}
    accountInfo : TDynRawBytes;
    {$ENDIF}
    balance: UInt64;
    updated_block: Cardinal;
    n_operation: Cardinal;
    name : TRawBytes;
    account_type : Word;
    previous_updated_block : Cardinal;
  End;
{$ELSE}
  TMemAccount = TAccount;
{$ENDIF}

procedure ToTMemAccount(Const source : TAccount; var dest : TMemAccount);
procedure ToTAccount(const source : TMemAccount; account_number : Cardinal; var dest : TAccount);

implementation

uses
  UAccountKeyStorage;

procedure ToTMemAccount(Const source : TAccount; var dest : TMemAccount);
{$IFDEF uselowmem}
Var raw : TRawBytes;
{$ENDIF}
begin
  {$IFDEF uselowmem}
  {$IFDEF useAccountKeyStorage}
  dest.accountInfoKS.state:=source.accountInfo.state;
  dest.accountInfoKS.accountKeyKS:=TAccountKeyStorage.KS.AddAccountKey(source.accountInfo.accountKey);
  dest.accountInfoKS.locked_until_block:=source.accountInfo.locked_until_block;
  dest.accountInfoKS.price:=source.accountInfo.price;
  dest.accountInfoKS.account_to_pay:=source.accountInfo.account_to_pay;
  dest.accountInfoKS.new_publicKeyKS:=TAccountKeyStorage.KS.AddAccountKey(source.accountInfo.new_publicKey);
  {$ELSE}
  TAccountComp.AccountInfo2RawString(source.accountInfo,raw);
  TBaseType.To256RawBytes(raw,dest.accountInfo);
  {$ENDIF}
  dest.balance := source.balance;
  dest.updated_block:=source.updated_block;
  dest.n_operation:=source.n_operation;
  dest.name:=source.name;
  dest.account_type:=source.account_type;
  dest.previous_updated_block:=source.previous_updated_block;
  {$ELSE}
  dest := source;
  {$ENDIF}
end;

procedure ToTAccount(const source : TMemAccount; account_number : Cardinal; var dest : TAccount);
{$IFDEF uselowmem}
var raw : TRawBytes;
{$ENDIF}
begin
  {$IFDEF uselowmem}
  dest.account:=account_number;
  {$IFDEF useAccountKeyStorage}
  dest.accountInfo.state:=source.accountInfoKS.state;
  dest.accountInfo.accountKey:=source.accountInfoKS.accountKeyKS^;
  dest.accountInfo.locked_until_block:=source.accountInfoKS.locked_until_block;
  dest.accountInfo.price:=source.accountInfoKS.price;
  dest.accountInfo.account_to_pay:=source.accountInfoKS.account_to_pay;
  dest.accountInfo.new_publicKey:=source.accountInfoKS.new_publicKeyKS^;
  {$ELSE}
  TBaseType.ToRawBytes(source.accountInfo,raw);
  TAccountComp.RawString2AccountInfo(raw,dest.accountInfo);
  {$ENDIF}
  dest.balance := source.balance;
  dest.updated_block:=source.updated_block;
  dest.n_operation:=source.n_operation;
  dest.name:=source.name;
  dest.account_type:=source.account_type;
  dest.previous_updated_block:=source.previous_updated_block;
  {$ELSE}
  dest := source;
  {$ENDIF}
end;

end.
