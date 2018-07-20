unit UAccountInfoKS;

interface

uses
  UAccountState, UAccountKey;

{$include MemoryReductionSettings.inc}

{$IFDEF uselowmem}
Type
  {$IFDEF useAccountKeyStorage}
  TAccountInfoKS = Record
    state : TAccountState;
    accountKeyKS: PAccountKey; // Change instead of TAccountKey
    locked_until_block : Cardinal;
    price : UInt64;
    account_to_pay : Cardinal;
    new_publicKeyKS : PAccountKey;
  end;
  {$ENDIF}
{$ENDIF}


implementation

end.
