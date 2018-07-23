unit UECPrivateKey;

interface

uses
  UOpenSSLdef, UECDSA_Public, URawBytes;

type
  // Skybuck: EC probably means ecliptic curve
  TECPrivateKey = Class
  private
    FPrivateKey: PEC_KEY;
    FEC_OpenSSL_NID : Word;
    procedure SetPrivateKey(const Value: PEC_KEY);
    function GetPublicKey: TECDSA_Public;
    function GetPublicKeyPoint: PEC_POINT;
  public
    Constructor Create;
    Procedure GenerateRandomPrivateKey(EC_OpenSSL_NID : Word);
    Destructor Destroy; override;
    Property PrivateKey : PEC_KEY read FPrivateKey;
    Property PublicKey : TECDSA_Public read GetPublicKey;
    Property PublicKeyPoint : PEC_POINT read GetPublicKeyPoint;
    Function SetPrivateKeyFromHexa(EC_OpenSSL_NID : Word; hexa : AnsiString) : Boolean;
    Property EC_OpenSSL_NID : Word Read FEC_OpenSSL_NID;
    class function IsValidPublicKey(PubKey : TECDSA_Public) : Boolean;
    Function ExportToRaw : TRawBytes;
    class Function ImportFromRaw(Const raw : TRawBytes) : TECPrivateKey; static;
  End;

implementation

uses
  UConst, UOpenSSL, Classes, UStreamOp, UCryptoException, SysUtils, ULog, UCrypto;

{ TECPrivateKey }

constructor TECPrivateKey.Create;
begin
  FPrivateKey := Nil;
  FEC_OpenSSL_NID := CT_Default_EC_OpenSSL_NID;
end;

destructor TECPrivateKey.Destroy;
begin
  if Assigned(FPrivateKey) then EC_KEY_free(FPrivateKey);
  inherited;
end;

function TECPrivateKey.ExportToRaw: TRawBytes;
Var ms : TStream;
  aux : TRawBytes;
begin
  ms := TMemoryStream.Create;
  Try
    ms.Write(FEC_OpenSSL_NID,sizeof(FEC_OpenSSL_NID));
    SetLength(aux,BN_num_bytes(EC_KEY_get0_private_key(FPrivateKey)));
    BN_bn2bin(EC_KEY_get0_private_key(FPrivateKey),@aux[1]);
    TStreamOp.WriteAnsiString(ms,aux);
    SetLength(Result,ms.Size);
    ms.Position := 0;
    ms.Read(Result[1],ms.Size);
  Finally
    ms.Free;
  End;
end;

procedure TECPrivateKey.GenerateRandomPrivateKey(EC_OpenSSL_NID : Word);
Var i : Integer;
begin
  if Assigned(FPrivateKey) then EC_KEY_free(FPrivateKey);
  FEC_OpenSSL_NID := EC_OpenSSL_NID;
  FPrivateKey := EC_KEY_new_by_curve_name(EC_OpenSSL_NID);
  i := EC_KEY_generate_key(FPrivateKey);
  if i<>1 then Raise ECryptoException.Create('Error generating new Random Private Key');
end;

function TECPrivateKey.GetPublicKey: TECDSA_Public;
var ps : PAnsiChar;
  BNx,BNy : PBIGNUM;
  ctx : PBN_CTX;
begin
  Result.EC_OpenSSL_NID := FEC_OpenSSL_NID;
  ctx := BN_CTX_new;
  BNx := BN_new;
  BNy := BN_new;
  Try
    EC_POINT_get_affine_coordinates_GFp(EC_KEY_get0_group(FPrivateKey),EC_KEY_get0_public_key(FPrivateKey),BNx,BNy,ctx);
    SetLength(Result.x,BN_num_bytes(BNx));
    BN_bn2bin(BNx,@Result.x[1]);
    SetLength(Result.y,BN_num_bytes(BNy));
    BN_bn2bin(BNy,@Result.y[1]);
  Finally
    BN_CTX_free(ctx);
    BN_free(BNx);
    BN_free(BNy);
  End;
end;

function TECPrivateKey.GetPublicKeyPoint: PEC_POINT;
begin
  Result := EC_KEY_get0_public_key(FPrivateKey);
end;

class function TECPrivateKey.ImportFromRaw(const raw: TRawBytes): TECPrivateKey;
Var ms : TStream;
  aux : TRawBytes;
  BNx : PBIGNUM;
  ECID : Word;
  PAC : PAnsiChar;
begin
  Result := Nil;
  ms := TMemoryStream.Create;
  Try
    ms.WriteBuffer(raw[1],length(raw));
    ms.Position := 0;
    if ms.Read(ECID,sizeof(ECID))<>sizeof(ECID) then exit;
    If TStreamOp.ReadAnsiString(ms,aux)<0 then exit;
    BNx := BN_bin2bn(PAnsiChar(aux),length(aux),nil);
    if assigned(BNx) then begin
      try
        PAC := BN_bn2hex(BNx);
        try
          Result := TECPrivateKey.Create;
          Try
            If Not Result.SetPrivateKeyFromHexa(ECID,PAC) then begin
              FreeAndNil(Result);
            end;
          Except
            On E:Exception do begin
              FreeAndNil(Result);
              // Note: Will not raise Exception, only will log it
              TLog.NewLog(lterror,ClassName,'Error importing private key from '+TCrypto.ToHexaString(raw)+' ECID:'+IntToStr(ECID)+' ('+E.ClassName+'): '+E.Message);
            end;
          end;
        finally
          OpenSSL_free(PAC);
        end;
      finally
        BN_free(BNx);
      end;
    end;
  Finally
    ms.Free;
  End;
end;

class function TECPrivateKey.IsValidPublicKey(PubKey: TECDSA_Public): Boolean;
Var BNx,BNy : PBIGNUM;
  ECG : PEC_GROUP;
  ctx : PBN_CTX;
  pub_key : PEC_POINT;
begin
  Result := False;
  BNx := BN_bin2bn(PAnsiChar(PubKey.x),length(PubKey.x),nil);
  if Not Assigned(BNx) then Exit;
  try
    BNy := BN_bin2bn(PAnsiChar(PubKey.y),length(PubKey.y),nil);
    if Not Assigned(BNy) then Exit;
    try
      ECG := EC_GROUP_new_by_curve_name(PubKey.EC_OpenSSL_NID);
      if Not Assigned(ECG) then Exit;
      try
        pub_key := EC_POINT_new(ECG);
        try
          if Not Assigned(pub_key) then Exit;
          ctx := BN_CTX_new;
          try
            Result := EC_POINT_set_affine_coordinates_GFp(ECG,pub_key,BNx,BNy,ctx)=1;
          finally
            BN_CTX_free(ctx);
          end;
        finally
          EC_POINT_free(pub_key);
        end;
      finally
        EC_GROUP_free(ECG);
      end;
    finally
      BN_free(BNy);
    end;
  finally
    BN_free(BNx);
  end;
end;

procedure TECPrivateKey.SetPrivateKey(const Value: PEC_KEY);
begin
  if Assigned(FPrivateKey) then EC_KEY_free(FPrivateKey);
  FPrivateKey := Value;
end;

function TECPrivateKey.SetPrivateKeyFromHexa(EC_OpenSSL_NID : Word; hexa : AnsiString) : Boolean;
var bn : PBIGNUM;
  ctx : PBN_CTX;
  pub_key : PEC_POINT;
begin
  Result := False;
  bn := BN_new;
  try
    if BN_hex2bn(@bn,PAnsiChar(hexa))=0 then Raise ECryptoException.Create('Invalid Hexadecimal value:'+hexa);

    if Assigned(FPrivateKey) then EC_KEY_free(FPrivateKey);
    FEC_OpenSSL_NID := EC_OpenSSL_NID;
    FPrivateKey := EC_KEY_new_by_curve_name(EC_OpenSSL_NID);
    If Not Assigned(FPrivateKey) then Exit;
    if EC_KEY_set_private_key(FPrivateKey,bn)<>1 then raise ECryptoException.Create('Invalid num to set as private key');
    //
    ctx := BN_CTX_new;
    pub_key := EC_POINT_new(EC_KEY_get0_group(FPrivateKey));
    try
      if EC_POINT_mul(EC_KEY_get0_group(FPrivateKey),pub_key,bn,nil,nil,ctx)<>1 then raise ECryptoException.Create('Error obtaining public key');
      EC_KEY_set_public_key(FPrivateKey,pub_key);
    finally
      BN_CTX_free(ctx);
      EC_POINT_free(pub_key);
    end;
  finally
    BN_free(bn);
  end;
  Result := True;
end;


end.
