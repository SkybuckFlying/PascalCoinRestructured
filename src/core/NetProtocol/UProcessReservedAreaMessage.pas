unit UProcessReservedAreaMessage;

interface

uses
  UNetConnection, UNetHeaderData, Classes;

type
  TProcessReservedAreaMessage = procedure (netData : TObject; senderConnection : TNetConnection; const HeaderData : TNetHeaderData; receivedData : TStream; responseData : TStream) of object;


implementation

end.
