unit UThreadCheckConnections;

interface

type
  TThreadCheckConnections = Class(TPCThread)
  private
    FNetData : TNetData;
    FLastCheckTS : TTickCount;
  protected
    procedure BCExecute; override;
  public
    Constructor Create(NetData : TNetData);
  End;

implementation

{ TThreadCheckConnections }

procedure TThreadCheckConnections.BCExecute;
Var l : TList;
  i, nactive,ndeleted,nserverclients : Integer;
  netconn : TNetConnection;
  netserverclientstop : TNetServerClient;
  newstats : TNetStatistics;
begin
  FLastCheckTS := TPlatform.GetTickCount;
  while (Not Terminated) do begin
    if ((TPlatform.GetTickCount>(FLastCheckTS+1000)) AND (Not FNetData.FIsDiscoveringServers)) then begin
      nactive := 0;
      ndeleted := 0;
      nserverclients := 0;
      netserverclientstop := Nil;
      FLastCheckTS := TPlatform.GetTickCount;
      If (FNetData.FNetConnections.TryLockList(100,l)) then begin
        try
          newstats := CT_TNetStatistics_NUL;
          for i := l.Count-1 downto 0 do begin
            netconn := TNetConnection(l.Items[i]);
            if (netconn is TNetClient) then begin
              if (netconn.Connected) then begin
                inc(newstats.ServersConnections);
                if (netconn.FHasReceivedData) then inc(newstats.ServersConnectionsWithResponse);
              end;
              if (Not TNetClient(netconn).Connected) And (netconn.CreatedTime+EncodeTime(0,0,5,0)<now) then begin
                // Free this!
                TNetClient(netconn).FinalizeConnection;
                inc(ndeleted);
              end else inc(nactive);
            end else if (netconn is TNetServerClient) then begin
              if (netconn.Connected) then begin
                inc(newstats.ClientsConnections);
              end;
              inc(nserverclients);
              if (Not netconn.FDoFinalizeConnection) then begin
                // Build 1.0.9 BUG-101 Only disconnect old versions prior to 1.0.9
                if not assigned(netserverclientstop) then begin
                  netserverclientstop := TNetServerClient(netconn);
                end else if (netconn.CreatedTime<netserverclientstop.CreatedTime) then begin
                  netserverclientstop := TNetServerClient(netconn);
                end;
              end;
            end;
          end;
          // Update stats:
          FNetData.FNetStatistics.ActiveConnections := newstats.ClientsConnections + newstats.ServersConnections;
          FNetData.FNetStatistics.ClientsConnections := newstats.ClientsConnections;
          FNetData.FNetStatistics.ServersConnections := newstats.ServersConnections;
          FNetData.FNetStatistics.ServersConnectionsWithResponse := newstats.ServersConnectionsWithResponse;
          // Must stop clients?
          if (nserverclients>FNetData.MaxServersConnected) And // This is to ensure there are more serverclients than clients
             ((nserverclients + nactive + ndeleted)>=FNetData.FMaxConnections) And (Assigned(netserverclientstop)) then begin
            TLog.NewLog(ltinfo,Classname,Format('Sending FinalizeConnection to NodeConnection %s created on %s (working time %s) - NetServerClients:%d Servers_active:%d Servers_deleted:%d',
              [netserverclientstop.Client.ClientRemoteAddr,FormatDateTime('hh:nn:ss',netserverclientstop.CreatedTime),
               FormatDateTime('hh:nn:ss',Now - netserverclientstop.CreatedTime),
               nserverclients,nactive,ndeleted]));
            netserverclientstop.FinalizeConnection;
          end;
        finally
          FNetData.FNetConnections.UnlockList;
        end;
        if (nactive<=FNetData.MaxServersConnected) And (Not Terminated) then begin
          // Discover
          FNetData.DiscoverServers;
        end;
      end;
    end;
    sleep(100);
  end;
end;

constructor TThreadCheckConnections.Create(NetData: TNetData);
begin
  FNetData := NetData;
  inherited Create(false);
end;


end.
