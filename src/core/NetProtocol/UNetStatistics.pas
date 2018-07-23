unit UNetStatistics;

interface

type
  // Skybuck: this should be turned into a class, might be a bit safer ;) for now I am gonna let it be and use the pointer type as a reference.
  TNetStatistics = Record
    ActiveConnections : Integer; // All connections wiht "connected" state
    ClientsConnections : Integer; // All clients connected to me like a server with "connected" state
    ServersConnections : Integer; // All servers where I'm connected
    ServersConnectionsWithResponse : Integer; // All servers where I'm connected and I've received data
    TotalConnections : Integer;
    TotalClientsConnections : Integer;
    TotalServersConnections : Integer;
    BytesReceived : Int64;
    BytesSend : Int64;
    NodeServersListCount : Integer;
    NodeServersDeleted : Integer;
  end;
  PNetStatistics = ^TNetStatistics;

var
  CT_TNetStatistics_NUL : TNetStatistics;

implementation

initialization
  Initialize(CT_TNetStatistics_NUL);

end.
