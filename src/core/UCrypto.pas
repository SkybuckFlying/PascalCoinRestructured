unit UCrypto;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{ Copyright (c) 2016 by Albert Molina

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.

  This unit is a part of Pascal Coin, a P2P crypto currency without need of
  historical operations.

  If you like it, consider a donation using BitCoin:
  16K3HCZRhFUtM8GdWRcfKeaa6KsuyxZaYk

  }

{$I config.inc}

interface

uses
  Classes, SysUtils, UOpenSSL, UOpenSSLdef, UECDSA_Public;

Type
  TRawBytes = AnsiString;
  PRawBytes = ^TRawBytes;

  TECDSA_SIG = record
     r: TRawBytes;
     s: TRawBytes;
  end; { record }


  { TCrypto }
  TCrypto = Class
  private
  public
    class function IsHexString(const AHexString: AnsiString) : boolean;
    class function ToHexaString(const raw : TRawBytes) : AnsiString;
    class function HexaToRaw(const HexaString : AnsiString) : TRawBytes; overload;
    class function HexaToRaw(const HexaString : AnsiString; out raw : TRawBytes) : Boolean; overload;
    class function DoSha256(p : PAnsiChar; plength : Cardinal) : TRawBytes; overload;
    class function DoSha256(const TheMessage : AnsiString) : TRawBytes; overload;
    class procedure DoSha256(const TheMessage : AnsiString; out ResultSha256 : TRawBytes);  overload;
    class function DoDoubleSha256(const TheMessage : AnsiString) : TRawBytes; overload;
    class procedure DoDoubleSha256(p : PAnsiChar; plength : Cardinal; out ResultSha256 : TRawBytes); overload;
    class function DoRipeMD160_HEXASTRING(const TheMessage : AnsiString) : TRawBytes; overload;
    class function DoRipeMD160AsRaw(p : PAnsiChar; plength : Cardinal) : TRawBytes; overload;
    class function DoRipeMD160AsRaw(const TheMessage : AnsiString) : TRawBytes; overload;
    class function PrivateKey2Hexa(Key : PEC_KEY) : AnsiString;
    class function ECDSASign(Key : PEC_KEY; const digest : AnsiString) : TECDSA_SIG;
    class function ECDSAVerify(EC_OpenSSL_NID : Word; PubKey : EC_POINT; const digest : AnsiString; Signature : TECDSA_SIG) : Boolean; overload;
    class function ECDSAVerify(PubKey : TECDSA_Public; const digest : AnsiString; Signature : TECDSA_SIG) : Boolean; overload;
    class procedure InitCrypto;
    class function IsHumanReadable(Const ReadableText : TRawBytes) : Boolean;
    class function EncodeSignature(const signature : TECDSA_SIG) : TRawBytes;
    class function DecodeSignature(const rawSignature : TRawBytes; out signature : TECDSA_SIG) : Boolean;
  End;


var
  CT_TECDSA_Public_Nul : TECDSA_Public; // initialized in initialization section
  CT_TECDSA_SIG_Nul : TECDSA_SIG;

implementation

uses
  ULog, UConst, UStreamOp, UPtrInt, UCryptoException; // UAccounts, UStreamOp;

Var _initialized : Boolean = false;

Procedure _DoInit;
var err : String;
 c : Cardinal;
Begin
  if Not (_initialized) then begin
    _initialized := true;
    If Not InitSSLFunctions then begin
      err := 'Cannot load OpenSSL library '+SSL_C_LIB;
      TLog.NewLog(ltError,'OpenSSL',err);
      Raise Exception.Create(err);
    end;
    If Not Assigned(OpenSSL_version_num) then begin
      err := 'OpenSSL library is not v1.1 version: '+SSL_C_LIB;
      TLog.NewLog(ltError,'OpenSSL',err);
      Raise Exception.Create(err);
    end;
    c := OpenSSL_version_num;
    if (c<$10100000) Or (c>$1010FFFF) then begin
      err := 'OpenSSL library is not v1.1 version ('+IntToHex(c,8)+'): '+SSL_C_LIB;
      TLog.NewLog(ltError,'OpenSSL',err);
      Raise Exception.Create(err);
    end;
  end;
End;


{ TCrypto }

{ New at Build 1.0.2
  Note: Delphi is slowly when working with Strings (allowing space)... so to
  increase speed we use a String as a pointer, and only increase speed if
  needed. Also the same with functions "GetMem" and "FreeMem" }
class procedure TCrypto.DoDoubleSha256(p: PAnsiChar; plength: Cardinal; out ResultSha256: TRawBytes);
Var PS : PAnsiChar;
begin
  If length(ResultSha256)<>32 then SetLength(ResultSha256,32);
  PS := @ResultSha256[1];
  SHA256(p,plength,PS);
  SHA256(PS,32,PS);
end;

class function TCrypto.DoDoubleSha256(const TheMessage: AnsiString): TRawBytes;
begin
  Result := DoSha256(DoSha256(TheMessage));
end;

class function TCrypto.DoRipeMD160_HEXASTRING(const TheMessage: AnsiString): TRawBytes;
Var PS : PAnsiChar;
  PC : PAnsiChar;
  i : Integer;
begin
  GetMem(PS,33);
  RIPEMD160(PAnsiChar(TheMessage),Length(TheMessage),PS);
  PC := PS;
  Result := '';
  for I := 1 to 20 do begin
    Result := Result + IntToHex(PtrInt(PC^),2);
    inc(PC);
  end;
  FreeMem(PS,33);
end;

class function TCrypto.DoRipeMD160AsRaw(p: PAnsiChar; plength: Cardinal): TRawBytes;
Var PS : PAnsiChar;
begin
  SetLength(Result,20);
  PS := @Result[1];
  RIPEMD160(p,plength,PS);
end;

class function TCrypto.DoRipeMD160AsRaw(const TheMessage: AnsiString): TRawBytes;
Var PS : PAnsiChar;
begin
  SetLength(Result,20);
  PS := @Result[1];
  RIPEMD160(PAnsiChar(TheMessage),Length(TheMessage),PS);
end;

class function TCrypto.DoSha256(p: PAnsiChar; plength: Cardinal): TRawBytes;
Var PS : PAnsiChar;
begin
  SetLength(Result,32);
  PS := @Result[1];
  SHA256(p,plength,PS);
end;

class function TCrypto.DoSha256(const TheMessage: AnsiString): TRawBytes;
Var PS : PAnsiChar;
begin
  SetLength(Result,32);
  PS := @Result[1];
  SHA256(PAnsiChar(TheMessage),Length(TheMessage),PS);
end;

{ New at Build 2.1.6
  Note: Delphi is slowly when working with Strings (allowing space)... so to
  increase speed we use a String as a pointer, and only increase speed if
  needed. Also the same with functions "GetMem" and "FreeMem" }
class procedure TCrypto.DoSha256(const TheMessage: AnsiString; out ResultSha256: TRawBytes);
Var PS : PAnsiChar;
begin
  If length(ResultSha256)<>32 then SetLength(ResultSha256,32);
  PS := @ResultSha256[1];
  SHA256(PAnsiChar(TheMessage),Length(TheMessage),PS);
end;

class function TCrypto.ECDSASign(Key: PEC_KEY; const digest: AnsiString): TECDSA_SIG;
Var PECS : PECDSA_SIG;
  p : PAnsiChar;
  i : Integer;
begin
  PECS := ECDSA_do_sign(PAnsiChar(digest),length(digest),Key);
  Try
    if PECS = Nil then raise ECryptoException.Create('Error signing');

    i := BN_num_bytes(PECS^._r);
    SetLength(Result.r,i);
    p := @Result.r[1];
    i := BN_bn2bin(PECS^._r,p);

    i := BN_num_bytes(PECS^._s);
    SetLength(Result.s,i);
    p := @Result.s[1];
    i := BN_bn2bin(PECS^._s,p);
  Finally
    ECDSA_SIG_free(PECS);
  End;
end;

class function TCrypto.ECDSAVerify(EC_OpenSSL_NID : Word; PubKey: EC_POINT; const digest: AnsiString; Signature: TECDSA_SIG): Boolean;
Var PECS : PECDSA_SIG;
  PK : PEC_KEY;
  {$IFDEF OpenSSL10}
  {$ELSE}
  bnr,bns : PBIGNUM;
  {$ENDIF}
begin
  PECS := ECDSA_SIG_new;
  Try
    {$IFDEF OpenSSL10}
    BN_bin2bn(PAnsiChar(Signature.r),length(Signature.r),PECS^._r);
    BN_bin2bn(PAnsiChar(Signature.s),length(Signature.s),PECS^._s);
    {$ELSE}
{    ECDSA_SIG_get0(PECS,@bnr,@bns);
    BN_bin2bn(PAnsiChar(Signature.r),length(Signature.r),bnr);
    BN_bin2bn(PAnsiChar(Signature.s),length(Signature.s),bns);}
    bnr := BN_bin2bn(PAnsiChar(Signature.r),length(Signature.r),nil);
    bns := BN_bin2bn(PAnsiChar(Signature.s),length(Signature.s),nil);
    if ECDSA_SIG_set0(PECS,bnr,bns)<>1 then Raise Exception.Create('Dev error 20161019-1 '+ERR_error_string(ERR_get_error(),nil));
    {$ENDIF}

    PK := EC_KEY_new_by_curve_name(EC_OpenSSL_NID);
    EC_KEY_set_public_key(PK,@PubKey);
    Case ECDSA_do_verify(PAnsiChar(digest),length(digest),PECS,PK) of
      1 : Result := true;
      0 : Result := false;
    Else
      raise ECryptoException.Create('Error on Verify');
    End;
    EC_KEY_free(PK);
  Finally
    ECDSA_SIG_free(PECS);
  End;
end;

class function TCrypto.ECDSAVerify(PubKey: TECDSA_Public; const digest: AnsiString; Signature: TECDSA_SIG): Boolean;
Var BNx,BNy : PBIGNUM;
  ECG : PEC_GROUP;
  ctx : PBN_CTX;
  pub_key : PEC_POINT;
begin
  BNx := BN_bin2bn(PAnsiChar(PubKey.x),length(PubKey.x),nil);
  BNy := BN_bin2bn(PAnsiChar(PubKey.y),length(PubKey.y),nil);

  ECG := EC_GROUP_new_by_curve_name(PubKey.EC_OpenSSL_NID);
  pub_key := EC_POINT_new(ECG);
  ctx := BN_CTX_new;
  if EC_POINT_set_affine_coordinates_GFp(ECG,pub_key,BNx,BNy,ctx)=1 then begin
    Result := ECDSAVerify(PubKey.EC_OpenSSL_NID, pub_key^,digest,signature);
  end else begin
    Result := false;
  end;
  BN_CTX_free(ctx);
  EC_POINT_free(pub_key);
  EC_GROUP_free(ECG);
  BN_free(BNx);
  BN_free(BNy);
end;

class function TCrypto.HexaToRaw(const HexaString: AnsiString): TRawBytes;
Var P : PAnsiChar;
 lc : AnsiString;
 i : Integer;
begin
  Result := '';
  if ((length(HexaString) MOD 2)<>0) Or (length(HexaString)=0) then exit;
  SetLength(result,length(HexaString) DIV 2);
  P := @Result[1];
  lc := LowerCase(HexaString);
  i := HexToBin(PAnsiChar(@lc[1]),P,length(Result));
  if (i<>(length(HexaString) DIV 2)) then begin
    TLog.NewLog(lterror,Classname,'Invalid HEXADECIMAL string result '+inttostr(i)+'<>'+inttostr(length(HexaString) DIV 2)+': '+HexaString);
    Result := '';
  end;
end;

class function TCrypto.HexaToRaw(const HexaString: AnsiString; out raw: TRawBytes): Boolean;
Var P : PAnsiChar;
 lc : AnsiString;
 i : Integer;
begin
  Result := False; raw := '';
  if ((length(HexaString) MOD 2)<>0) then Exit;
  if (length(HexaString)=0) then begin
    Result := True;
    exit;
  end;
  SetLength(raw,length(HexaString) DIV 2);
  P := @raw[1];
  lc := LowerCase(HexaString);
  i := HexToBin(PAnsiChar(@lc[1]),P,length(raw));
  Result := (i = (length(HexaString) DIV 2));
end;

class procedure TCrypto.InitCrypto;
begin
  _DoInit;
end;

class function TCrypto.IsHumanReadable(const ReadableText: TRawBytes): Boolean;
Var i : Integer;
Begin
  Result := true;
  for i := 1 to length(ReadableText) do begin
    if (ord(ReadableText[i])<32) Or (ord(ReadableText[i])>=255) then begin
      Result := false;
      Exit;
    end;
  end;
end;

class function TCrypto.EncodeSignature(const signature: TECDSA_SIG): TRawBytes;
Var ms : TStream;
begin
  ms := TMemoryStream.Create;
  Try
    TStreamOp.WriteAnsiString(ms,signature.r);
    TStreamOp.WriteAnsiString(ms,signature.s);
    Result := TStreamOp.SaveStreamToRaw(ms);
  finally
    ms.Free;
  end;
end;

class function TCrypto.DecodeSignature(const rawSignature : TRawBytes; out signature : TECDSA_SIG) : Boolean;
var ms : TStream;
begin
  signature := CT_TECDSA_SIG_Nul;
  Result := False;
  ms := TMemoryStream.Create;
  Try
    TStreamOp.LoadStreamFromRaw(ms,rawSignature);
    ms.Position:=0;
    if TStreamOp.ReadAnsiString(ms,signature.r)<0 then Exit;
    if TStreamOp.ReadAnsiString(ms,signature.s)<0 then Exit;
    if ms.Position<ms.Size then Exit; // Invalid position
    Result := True;
  finally
    ms.Free;
  end;
end;

class function TCrypto.PrivateKey2Hexa(Key: PEC_KEY): AnsiString;
Var p : PAnsiChar;
begin
  p := BN_bn2hex(EC_KEY_get0_private_key(Key));
//  p := BN_bn2hex(Key^.priv_key);
  Result := strpas(p);
  OPENSSL_free(p);
end;

class function TCrypto.ToHexaString(const raw: TRawBytes): AnsiString;
Var i : Integer;
  s : AnsiString;
  b : Byte;
begin
  SetLength(Result,length(raw)*2);
  for i := 0 to length(raw)-1 do begin
    b := Ord(raw[i+1]);
    s := IntToHex(b,2);
    Result[(i*2)+1] := s[1];
    Result[(i*2)+2] := s[2];
  end;
end;

class function TCrypto.IsHexString(const AHexString: AnsiString) : boolean;
var
  i : Integer;
begin
  Result := true;
  for i := 1 to length(AHexString) do
    if (NOT (AHexString[i] in ['0'..'9'])) AND
       (NOT (AHexString[i] in ['a'..'f'])) AND
       (NOT (AHexString[i] in ['A'..'F'])) then begin
       Result := false;
       exit;
    end;
end;


initialization
  Initialize(CT_TECDSA_Public_Nul);
  Initialize(CT_TECDSA_SIG_Nul);

  Randomize; // Initial random generator based on system time
finalization

end.
