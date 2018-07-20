unit UMultiOpChangeInfo;

interface

uses
  UOpChangeAccountInfoType, UAccountKey, URawBytes, UCrypto;

type
  TMultiOpChangeInfo = Record
    Account: Cardinal;
    N_Operation : Cardinal;
    Changes_type : TOpChangeAccountInfoTypes; // bits mask. $0001 = New account key , $0002 = New name , $0004 = New type
    New_Accountkey: TAccountKey;  // If (changes_mask and $0001)=$0001 then change account key
    New_Name: TRawBytes;          // If (changes_mask and $0002)=$0002 then change name
    New_Type: Word;               // If (changes_mask and $0004)=$0004 then change type
    Seller_Account : Int64;
    Account_Price : Int64;
    Locked_Until_Block : Cardinal;
    Fee: Int64;
    Signature: TECDSA_SIG;
  end;
  TMultiOpChangesInfo = Array of TMultiOpChangeInfo;

implementation

end.
