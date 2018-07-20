unit UAccounts;

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

interface

uses
  Classes, UConst, UCrypto, SyncObjs, UThread, UBaseTypes, UOperationBlock, UOrderedRawList, UAccountPreviousBlockInfo, UAccountKey, UAccountState, UAccount, UAccountInfo, UPCSafeBox, UBlockAccount, UPCSafeBoxHeader;
{$I config.inc}

Type






  {
    Protocol 2:
    Introducing OperationBlock info on the safebox, this will allow checkpointing a safebox because
    each row of the safebox (TBlockAccount) will have data about how to calculate
    its PoW, so next row will use row-1 info to check it's good generated thanks to PoW

    This solution does not include operations, but include operations_hash value,
    that is a SHA256 of operations.

    If someone wants to change the safebox and spam, will need to find values
    to alter safebox accounts of last checkpoint and also find new blocks prior
    to honest nodes, that will be only accepted by nodes that does not have
    last blocks (only fresh nodes). This is a very hard job and not efficient
    because usually there will be few new fresh nodes per period, so only
    can spam new fresh nodes because old nodes does not need to download
    a checkpointing.
    This solution was created by Herman Schoenfeld (Thanks!)
  }




  { Estimated TAccount size:
    4 + 200 (max aprox) + 8 + 4 + 4 = 220 max aprox
    Estimated TBlockAccount size:
    4 + (5 * 220) + 4 + 32 = 1140 max aprox
  }





  // Maintans a Cardinal ordered (without duplicates) list with TRawData each

  { TOrderedCardinalListWithRaw }

  TOrderedCardinalListWithRaw = Class
  private
    FList : TList;
    Function Find(value : Cardinal; var Index: Integer): Boolean;
  public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Clear;
    Function Add(const Value: Cardinal; const RawData : TRawBytes) : Integer;
    Function Count : Integer;
    Function GetCardinal(index : Integer) : Cardinal;
    function GetRaw(index : Integer) : TRawBytes;
    Procedure Delete(index : Integer);
    Function IndexOf(value : Cardinal) : Integer;
    Function IndexOfRaw(const RawData : TRawBytes) : Integer;
  end;

  // SafeBox is a box that only can be updated using SafeBoxTransaction, and this
  // happens only when a new BlockChain is included. After this, a new "SafeBoxHash"
  // is created, so each SafeBox has a unique SafeBoxHash

  { TPCSafeBox }






var
  CT_SafeBoxChunkIdentificator : string = 'SafeBoxChunk';


implementation

uses
  SysUtils, ULog, UOpenSSLdef, UOpenSSL, UAccountKeyStorage, math, UTickCount, UBaseType, UAccountComp;







{ TOrderedCardinalListWithRaw }

Type TCardinalListData = Record
    value : Cardinal;
    rawData : TRawBytes;
  End;
  PCardinalListData = ^TCardinalListData;

function TOrderedCardinalListWithRaw.Find(value: Cardinal; var Index: Integer): Boolean;
var L, H, I: Integer;
  c : Integer;
begin
  Result := False;
  L := 0;
  H := FList.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    c := Int64(PCardinalListData(FList[I])^.value) - Int64(Value);
    if C < 0 then L := I + 1 else
    begin
      H := I - 1;
      if C = 0 then
      begin
        Result := True;
        L := I;
      end;
    end;
  end;
  Index := L;
end;

constructor TOrderedCardinalListWithRaw.Create;
begin
  FList := TList.Create;
end;

destructor TOrderedCardinalListWithRaw.Destroy;
begin
  Clear;
  FreeAndNil(FList);
  inherited Destroy;
end;

procedure TOrderedCardinalListWithRaw.Clear;
Var i : Integer;
  P : PCardinalListData;
begin
  for i:=0 to FList.Count-1 do begin
    P := FList[i];
    P^.rawData:='';
    Dispose(P);
  end;
  FList.Clear;
end;

function TOrderedCardinalListWithRaw.Add(const Value: Cardinal; const RawData: TRawBytes): Integer;
Var P : PCardinalListData;
begin
  If Find(Value,Result) then begin
    P := FList[Result];
    P^.rawData:=RawData;
  end else begin
    New(P);
    P^.value:=Value;
    P^.rawData:=rawData;
    FList.Insert(Result,P);
  end;
end;

function TOrderedCardinalListWithRaw.Count: Integer;
begin
  Result := FList.Count;
end;

function TOrderedCardinalListWithRaw.GetCardinal(index: Integer): Cardinal;
begin
  Result := PCardinalListData(FList[index])^.value;
end;

function TOrderedCardinalListWithRaw.GetRaw(index: Integer): TRawBytes;
begin
  Result := PCardinalListData(FList[index])^.rawData;
end;

procedure TOrderedCardinalListWithRaw.Delete(index: Integer);
Var P : PCardinalListData;
begin
  P := PCardinalListData( FList[index] );
  FList.Delete(index);
  Dispose(P);
end;

function TOrderedCardinalListWithRaw.IndexOf(value: Cardinal): Integer;
begin
  If Not Find(value,Result) then Result := -1;
end;

function TOrderedCardinalListWithRaw.IndexOfRaw(const RawData: TRawBytes): Integer;
begin
  For Result := 0 to FList.Count-1 do begin
    If TBaseType.BinStrComp( PCardinalListData( FList[Result] )^.rawData , RawData ) = 0 then Exit;
  end;
  Result := -1;
end;

initialization

end.
