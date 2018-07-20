unit UPascalCoinProtocol;

interface

uses
  URawBytes, UOperationBlock;

type
  { TPascalCoinProtocol }
  TPascalCoinProtocol = Class
  public
    Class Function GetRewardForNewLine(line_index: Cardinal): UInt64;
    Class Function TargetToCompact(target: TRawBytes): Cardinal;
    Class Function TargetFromCompact(encoded: Cardinal): TRawBytes;
    Class Function GetNewTarget(vteorical, vreal: Cardinal; protocol_version : Integer; isSlowMovement : Boolean; Const actualTarget: TRawBytes): TRawBytes;
    Class Procedure CalcProofOfWork_Part1(const operationBlock : TOperationBlock; out Part1 : TRawBytes);
    Class Procedure CalcProofOfWork_Part3(const operationBlock : TOperationBlock; out Part3 : TRawBytes);
    Class Procedure CalcProofOfWork(const operationBlock : TOperationBlock; out PoW : TRawBytes);
    Class Function IsValidMinerBlockPayload(const newBlockPayload : TRawBytes) : Boolean;
    class procedure GetRewardDistributionForNewBlock(const OperationBlock : TOperationBlock; out acc_0_miner_reward, acc_4_dev_reward : Int64; out acc_4_for_dev : Boolean);
  end;

implementation

uses
  UBigNum, UConst, Classes, UAccountComp, UCrypto, SysUtils;

{ TPascalCoinProtocol }

class function TPascalCoinProtocol.GetNewTarget(vteorical, vreal: Cardinal; protocol_version : Integer; isSlowMovement : Boolean; const actualTarget: TRawBytes): TRawBytes;
Var
  bnact, bnaux: TBigNum;
  tsTeorical, tsReal, factor, factorMin, factorMax, factorDivider: Int64;
begin
  { Given a teorical time in seconds (vteorical>0) and a real time in seconds (vreal>0)
    and an actual target, calculates a new target
    by % of difference of teorical vs real.

    Increment/decrement is adjusted to +-200% in a full CT_CalcNewTargetBlocksAverage round
    ...so each new target is a maximum +-(100% DIV (CT_CalcNewTargetBlocksAverage DIV 2)) of
    previous target. This makes target more stable.

    }
  tsTeorical := vteorical;
  tsReal := vreal;

  { On protocol 1,2 the increment was limited in a integer value between -10..20
    On protocol 3 we increase decimals, so increment could be a integer
    between -1000..2000, using 2 more decimals for percent. Also will introduce
    a "isSlowMovement" variable that will limit to a maximum +-0.5% increment}
  if (protocol_version<CT_PROTOCOL_3) then begin
    factorDivider := 1000;
    factor := (((tsTeorical - tsReal) * 1000) DIV (tsTeorical)) * (-1);

    { Important: Note that a -500 is the same that divide by 2 (-100%), and
      1000 is the same that multiply by 2 (+100%), so we limit increase
      in a limit [-500..+1000] for a complete (CT_CalcNewTargetBlocksAverage DIV 2) round }
    if CT_CalcNewTargetBlocksAverage>1 then begin
      factorMin := (-500) DIV (CT_CalcNewTargetBlocksAverage DIV 2);
      factorMax := (1000) DIV (CT_CalcNewTargetBlocksAverage DIV 2);
    end else begin
      factorMin := (-500);
      factorMax := (1000);
    end;
  end else begin
    // Protocol 3:
    factorDivider := 100000;
    If (isSlowMovement) then begin
      // Limit to 0.5% instead of 2% (When CT_CalcNewTargetBlocksAverage = 100)
      factorMin := (-50000) DIV (CT_CalcNewTargetBlocksAverage * 2);
      factorMax := (100000) DIV (CT_CalcNewTargetBlocksAverage * 2);
    end else begin
      if CT_CalcNewTargetBlocksAverage>1 then begin
        factorMin := (-50000) DIV (CT_CalcNewTargetBlocksAverage DIV 2);
        factorMax := (100000) DIV (CT_CalcNewTargetBlocksAverage DIV 2);
      end else begin
        factorMin := (-50000);
        factorMax := (100000);
      end;
    end;
  end;

  factor := (((tsTeorical - tsReal) * factorDivider) DIV (tsTeorical)) * (-1);

  if factor < factorMin then factor := factorMin
  else if factor > factorMax then factor := factorMax
  else if factor=0 then begin
    Result := actualTarget;
    exit;
  end;

  // Calc new target by increasing factor (-500 <= x <= 1000)
  bnact := TBigNum.Create(0);
  try
    bnact.RawValue := actualTarget;
    bnaux := bnact.Copy;
    try
      bnact.Multiply(factor).Divide(factorDivider).Add(bnaux);
    finally
      bnaux.Free;
    end;
    // Adjust to TargetCompact limitations:
    Result := TargetFromCompact(TargetToCompact(bnact.RawValue));
  finally
    bnact.Free;
  end;
end;

class procedure TPascalCoinProtocol.CalcProofOfWork_Part1(const operationBlock: TOperationBlock; out Part1: TRawBytes);
var ms : TMemoryStream;
  s : AnsiString;
begin
  ms := TMemoryStream.Create;
  try
    // Part 1
    ms.Write(operationBlock.block,Sizeof(operationBlock.block)); // Little endian
    s := TAccountComp.AccountKey2RawString(operationBlock.account_key);
    ms.WriteBuffer(s[1],length(s));
    ms.Write(operationBlock.reward,Sizeof(operationBlock.reward)); // Little endian
    ms.Write(operationBlock.protocol_version,Sizeof(operationBlock.protocol_version)); // Little endian
    ms.Write(operationBlock.protocol_available,Sizeof(operationBlock.protocol_available)); // Little endian
    ms.Write(operationBlock.compact_target,Sizeof(operationBlock.compact_target)); // Little endian
    SetLength(Part1,ms.Size);
    ms.Position:=0;
    ms.Read(Part1[1],ms.Size);
  finally
    ms.Free;
  end;
end;

class procedure TPascalCoinProtocol.CalcProofOfWork_Part3(const operationBlock: TOperationBlock; out Part3: TRawBytes);
var ms : TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    ms.WriteBuffer(operationBlock.initial_safe_box_hash[1],length(operationBlock.initial_safe_box_hash));
    ms.WriteBuffer(operationBlock.operations_hash[1],length(operationBlock.operations_hash));
    // Note about fee: Fee is stored in 8 bytes, but only digest first 4 low bytes
    ms.Write(operationBlock.fee,4);
    SetLength(Part3,ms.Size);
    ms.Position := 0;
    ms.ReadBuffer(Part3[1],ms.Size);
  finally
    ms.Free;
  end;
end;

class procedure TPascalCoinProtocol.CalcProofOfWork(const operationBlock: TOperationBlock; out PoW: TRawBytes);
var ms : TMemoryStream;
  s : AnsiString;
begin
  ms := TMemoryStream.Create;
  try
    // Part 1
    ms.Write(operationBlock.block,Sizeof(operationBlock.block)); // Little endian
    s := TAccountComp.AccountKey2RawString(operationBlock.account_key);
    ms.WriteBuffer(s[1],length(s));
    ms.Write(operationBlock.reward,Sizeof(operationBlock.reward)); // Little endian
    ms.Write(operationBlock.protocol_version,Sizeof(operationBlock.protocol_version)); // Little endian
    ms.Write(operationBlock.protocol_available,Sizeof(operationBlock.protocol_available)); // Little endian
    ms.Write(operationBlock.compact_target,Sizeof(operationBlock.compact_target)); // Little endian
    // Part 2
    ms.WriteBuffer(operationBlock.block_payload[1],length(operationBlock.block_payload));
    // Part 3
    ms.WriteBuffer(operationBlock.initial_safe_box_hash[1],length(operationBlock.initial_safe_box_hash));
    ms.WriteBuffer(operationBlock.operations_hash[1],length(operationBlock.operations_hash));
    // Note about fee: Fee is stored in 8 bytes (Int64), but only digest first 4 low bytes
    ms.Write(operationBlock.fee,4);
    ms.Write(operationBlock.timestamp,4);
    ms.Write(operationBlock.nonce,4);
    TCrypto.DoDoubleSha256(ms.Memory,ms.Size,PoW);
  finally
    ms.Free;
  end;
end;

class function TPascalCoinProtocol.IsValidMinerBlockPayload(const newBlockPayload: TRawBytes): Boolean;
var i : Integer;
begin
  Result := False;
  if Length(newBlockPayload)>CT_MaxPayloadSize then Exit;
  // Checking Miner Payload valid chars
  for i := 1 to length(newBlockPayload) do begin
    if Not (newBlockPayload[i] in [#32..#254]) then begin
      exit;
    end;
  end;
  Result := True;
end;

class procedure TPascalCoinProtocol.GetRewardDistributionForNewBlock(const OperationBlock : TOperationBlock; out acc_0_miner_reward, acc_4_dev_reward : Int64; out acc_4_for_dev : Boolean);
begin
  if OperationBlock.protocol_version<CT_PROTOCOL_3 then begin
    acc_0_miner_reward := OperationBlock.reward + OperationBlock.fee;
    acc_4_dev_reward := 0;
    acc_4_for_dev := False;
  end else begin
    acc_4_dev_reward := (OperationBlock.reward * CT_Protocol_v3_PIP11_Percent) DIV 100;
    acc_0_miner_reward := OperationBlock.reward + OperationBlock.fee - acc_4_dev_reward;
    acc_4_for_dev := True;
  end;
end;

class function TPascalCoinProtocol.GetRewardForNewLine(line_index: Cardinal): UInt64;
Var n, i : Cardinal;
begin
  {$IFDEF TESTNET}
  // TESTNET used (line_index +1), but PRODUCTION must use (line_index)
  n := (line_index + 1) DIV CT_NewLineRewardDecrease;  // TESTNET BAD USE (line_index + 1)
  {$ELSE}
  n := line_index DIV CT_NewLineRewardDecrease; // FOR PRODUCTION
  {$ENDIF}
  Result := CT_FirstReward;
  for i := 1 to n do begin
    Result := Result DIV 2;
  end;
  if (Result < CT_MinReward) then
    Result := CT_MinReward;
end;

class function TPascalCoinProtocol.TargetFromCompact(encoded: Cardinal): TRawBytes;
Var
  nbits, high, offset, i: Cardinal;
  bn: TBigNum;
  raw : TRawBytes;
begin
  {
    Compact Target is a 4 byte value that tells how many "0" must have the hash at left if presented in binay format.
    First byte indicates haw many "0 bits" are on left, so can be from 0x00 to 0xE7
    (Because 24 bits are reserved for 3 bytes, and 1 bit is implicit, max: 256-24-1=231=0xE7)
    Next 3 bytes indicates next value in XOR, stored in RAW format

    Example: If we want a hash lower than 0x0000 0000 0000 65A0 A2F4 +29 bytes
    Binary "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0110 0101 1010 0000 1010 0010 1111 0100"
    That is 49 zeros on left before first 1. So first byte is 49 decimal = 0x31
    After we have "110 0101 1010 0000 1010 0010 1111 0100 1111 0100" but we only can accept first 3 bytes,
    also note that first "1" is implicit, so value is transformed in
    binary as "10 0101 1010 0000 1010 0010 11" that is 0x96828B
    But note that we must XOR this value, so result offset is: 0x697D74
    Compacted value is: 0x31697D74

    When translate compact target back to target: ( 0x31697D74 )
    0x31 = 49 bits at "0", then 1 bit at "1" followed by XOR 0x697D74 = 0x96828B
    49 "0" bits "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0"
    0x96828B "1001 0110 1000 0010 1000 1011"
    Hash target = "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0110 0101 1010 0000 1010 0010 11.. ...."
    Fill last "." with "1"
    Hash target = "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0110 0101 1010 0000 1010 0010 1111 1111"
    Hash target = 0x00 00 00 00 00 00 65 A0 A2 FF + 29 bytes
    Note that is not exactly the same than expected due to compacted format
    }
  nbits := encoded shr 24;
  i := CT_MinCompactTarget shr 24;
  if nbits < i then
    nbits := i; // min nbits
  if nbits > 231 then
    nbits := 231; // max nbits

  offset := (encoded shl 8) shr 8;
  // Make a XOR at offset and put a "1" on the left
  offset := ((offset XOR $00FFFFFF) OR ($01000000));

  bn := TBigNum.Create(offset);
  Try
    bn.LShift(256 - nbits - 25);
    raw := bn.RawValue;
    SetLength(Result,32);
    FillChar(Result[1],32,0);
    for i:=1 to Length(raw) do begin
      result[i+32-length(raw)] := raw[i];
    end;
  Finally
    bn.Free;
  End;
end;

class function TPascalCoinProtocol.TargetToCompact(target: TRawBytes): Cardinal;
Var
  bn, bn2: TBigNum;
  i: Int64;
  nbits: Cardinal;
  c: AnsiChar;
  raw : TRawBytes;
  j : Integer;
begin
  { See instructions in explanation of TargetFromCompact }
  Result := 0;
  if length(target)>32 then begin
    raise Exception.Create('Invalid target to compact: '+TCrypto.ToHexaString(target)+' ('+inttostr(length(target))+')');
  end;
  SetLength(raw,32);
  FillChar(raw[1],32,0);
  for j:=1 to length(target) do begin
    raw[j+32-length(target)] := target[j];
  end;
  target := raw;

  bn := TBigNum.Create(0);
  bn2 := TBigNum.Create('8000000000000000000000000000000000000000000000000000000000000000'); // First bit 1 followed by 0
  try
    bn.RawValue := target;
    nbits := 0;
    while (bn.CompareTo(bn2) < 0) And (nbits < 231) do
    begin
      bn2.RShift(1);
      inc(nbits);
    end;
    i := CT_MinCompactTarget shr 24;
    if (nbits < i) then
    begin
      Result := CT_MinCompactTarget;
      exit;
    end;
    bn.RShift((256 - 25) - nbits);
    Result := (nbits shl 24) + ((bn.value AND $00FFFFFF) XOR $00FFFFFF);
  finally
    bn.Free;
    bn2.Free;
  end;
end;

end.
