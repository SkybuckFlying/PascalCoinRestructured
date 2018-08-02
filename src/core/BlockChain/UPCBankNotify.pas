unit UPCBankNotify;

interface

uses
  Classes;

type
  TPCBankNotify = Class
  private
    FOnNewBlock: TNotifyEvent;
  protected

  public
    Constructor Create;
    Destructor Destroy; Override;

    // Skybuck: moved to here so UPascalCoinBank can access it
    Procedure NotifyNewBlock;

    Property OnNewBlock : TNotifyEvent read FOnNewBlock write FOnNewBlock;
  End;

implementation

uses
  UPascalCoinBank;

{ TPCBankNotify }

constructor TPCBankNotify.Create;
begin
  inherited;
end;

destructor TPCBankNotify.Destroy;
begin
  inherited;
end;

procedure TPCBankNotify.NotifyNewBlock;
begin
  if Assigned(FOnNewBlock) Then FOnNewBlock(Nil);
end;

end.
