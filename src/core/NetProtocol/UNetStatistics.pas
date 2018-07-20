unit UNetStatistics;

interface

type
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

var
  CT_TNetStatistics_NUL : TNetStatistics;

implementation

initialization
  Initialize(CT_TNetStatistics_NUL);

end.
