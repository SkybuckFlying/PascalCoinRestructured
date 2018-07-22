unit UProcessReservedAreaMessage;

interface

uses
  UNetData;

type
  TProcessReservedAreaMessage = procedure (netData : TNetData; senderConnection : TNetConnection; const HeaderData : TNetHeaderData; receivedData : TStream; responseData : TStream) of object;


implementation

end.
