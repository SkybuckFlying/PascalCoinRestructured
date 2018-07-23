unit UProcessReservedAreaMessage;

interface

uses
  UNetData; // circular reference problem 4 , making git commit.

type
  TProcessReservedAreaMessage = procedure (netData : TNetData; senderConnection : TNetConnection; const HeaderData : TNetHeaderData; receivedData : TStream; responseData : TStream) of object;


implementation

end.
