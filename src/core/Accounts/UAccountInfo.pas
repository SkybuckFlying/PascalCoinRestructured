unit UAccountInfo;

interface

uses
  UAccountState, UAccountKey;

type
  TAccountInfo = Record
    state : TAccountState;
    accountKey: TAccountKey;
    // Trade info, only when state=as_ForSale
    locked_until_block : Cardinal; // 0 = Not locked
    price : UInt64;                // 0 = invalid price
    account_to_pay : Cardinal;     // <> itself
    new_publicKey : TAccountKey;
  end;

var
  CT_AccountInfo_NUL : TAccountInfo;

implementation

initialization
  Initialize(CT_AccountInfo_NUL);

end.
