unit UThreadGetNewBlockChainFromClient;

interface

type
  { TThreadGetNewBlockChainFromClient }
  TThreadGetNewBlockChainFromClient = Class(TPCThread)
  protected
    procedure BCExecute; override;
  public
    Constructor Create;
  End;

implementation

{ TThreadGetNewBlockChainFromClient }

procedure TThreadGetNewBlockChainFromClient.BCExecute;
Var i,j : Integer;
  maxWork : UInt64;
  candidates : TList;
  lop : TOperationBlock;
  nc : TNetConnection;
begin
  // Search better candidates:
  candidates := TList.Create;
  try
    lop := CT_OperationBlock_NUL;
    TNetData.NetData.FMaxRemoteOperationBlock := CT_OperationBlock_NUL;
    // First round: Find by most work
    maxWork := 0;
    j := TNetData.NetData.ConnectionsCountAll;
    nc := Nil;
    for i := 0 to j - 1 do begin
      if TNetData.NetData.GetConnection(i,nc) then begin
        if (nc.FRemoteAccumulatedWork>maxWork) And (nc.FRemoteAccumulatedWork>TNode.Node.Bank.SafeBox.WorkSum) then begin
          maxWork := nc.FRemoteAccumulatedWork;
        end;
        // Preventing downloading
        if nc.FIsDownloadingBlocks then exit;
      end;
    end;
    if (maxWork>0) then begin
      for i := 0 to j - 1 do begin
        If TNetData.NetData.GetConnection(i,nc) then begin
          if (nc.FRemoteAccumulatedWork>=maxWork) then begin
            candidates.Add(nc);
            lop := nc.FRemoteOperationBlock;
          end;
        end;
      end;
    end;
    // Second round: Find by most height
    if candidates.Count=0 then begin
      for i := 0 to j - 1 do begin
        if (TNetData.NetData.GetConnection(i,nc)) then begin
          if (nc.FRemoteOperationBlock.block>=TNode.Node.Bank.BlocksCount) And
             (nc.FRemoteOperationBlock.block>=lop.block) then begin
             lop := nc.FRemoteOperationBlock;
          end;
        end;
      end;
      if (lop.block>0) then begin
        for i := 0 to j - 1 do begin
          If (TNetData.NetData.GetConnection(i,nc)) then begin
            if (nc.FRemoteOperationBlock.block>=lop.block) then begin
               candidates.Add(nc);
            end;
          end;
        end;
      end;
    end;
    TNetData.NetData.FMaxRemoteOperationBlock := lop;
    if (candidates.Count>0) then begin
      // Random a candidate
      i := 0;
      if (candidates.Count>1) then i := Random(candidates.Count); // i = 0..count-1
      nc := TNetConnection(candidates[i]);
      TNetData.NetData.GetNewBlockChainFromClient(nc,Format('Candidate block: %d sum: %d',[nc.FRemoteOperationBlock.block,nc.FRemoteAccumulatedWork]));
    end;
  finally
    candidates.Free;
  end;
end;

constructor TThreadGetNewBlockChainFromClient.Create;
begin
  Inherited Create(True);
  FreeOnTerminate := true;
  Suspended := false;
end;


end.
