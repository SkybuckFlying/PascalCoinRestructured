unit UECDSA_Public;

interface

uses
  URawBytes;

type
  TECDSA_Public = record
     EC_OpenSSL_NID : Word;
     x: TRawBytes;
     y: TRawBytes;
  end;
  PECDSA_Public = ^TECDSA_Public;

var
  CT_TECDSA_Public_Nul : TECDSA_Public; // initialized in initialization section

implementation

initialization
  Initialize(CT_TECDSA_Public_Nul);


end.
