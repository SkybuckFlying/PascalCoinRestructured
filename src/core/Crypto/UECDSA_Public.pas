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

implementation

end.
