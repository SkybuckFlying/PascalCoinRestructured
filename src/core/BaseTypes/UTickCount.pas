unit UTickCount;

interface

type
  // TickCount is platform specific (32 or 64 bits)
  TTickCount = {$IFDEF CPU64}QWord{$ELSE}Cardinal{$ENDIF};

implementation

end.
