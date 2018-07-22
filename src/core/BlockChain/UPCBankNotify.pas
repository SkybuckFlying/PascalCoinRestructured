unit UPCBankNotify;

interface

uses
  Classes, UPCBank;

type
  TPCBankNotify = Class(TComponent)
  private
    FOnNewBlock: TNotifyEvent;
    FBank: TPCBank;
    procedure SetBank(const Value: TPCBank);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); Override;
  public
    Constructor Create(AOwner: TComponent); Override;
    Destructor Destroy; Override;

    // Skybuck: moved to here so UPCBank can access it
    Procedure NotifyNewBlock;

    Property Bank : TPCBank read FBank write SetBank;
    Property OnNewBlock : TNotifyEvent read FOnNewBlock write FOnNewBlock;
  End;

implementation

{ TPCBankNotify }

constructor TPCBankNotify.Create(AOwner: TComponent);
begin
  inherited;
  FBank := Nil;
end;

destructor TPCBankNotify.Destroy;
begin
  Bank := Nil;
  inherited;
end;

procedure TPCBankNotify.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (operation=opremove) then if AComponent=FBank then FBank:=nil;
end;

procedure TPCBankNotify.NotifyNewBlock;
begin
  if Assigned(FOnNewBlock) Then FOnNewBlock(Bank);
end;

procedure TPCBankNotify.SetBank(const Value: TPCBank);
begin
  if Assigned(FBank) then begin
    FBank.NotifyList.Remove(Self);
    FBank.RemoveFreeNotification(Self);
  end;
  FBank := Value;
  if Assigned(FBank) then begin
    FBank.FreeNotification(Self);
    FBank.NotifyList.Add(Self);
  end;
end;

end.
