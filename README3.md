# Pascal Coin (Skybuck)(Restructured): Clone of SkybuckFlying/PascalCoin

Massive restructuring of PascalCoin.

Do not run current source files, they are buggy and need to be fixed first.

Search for "PROBLEMS" to find problems that need to be fixed first.

Many references to references to references reduced to just one reference:

Example:

TNode.Node to PascalCoinNode

TNode.Node.Bank to PascalCoinBank

TNode.Node.Bank.SafeBoxBox to PascalCoinSafeBox

TNetData.NetData to PascalNetData

Some threading re-worked (untested)

Many if not all circular references removed and fixed.

PCOperationComp modified to always work on PascalCoinNode/PascalCoinBank/PascalCoinSafeBox and so forth.

This leads currently to problem in GetNewBank and such which needs to be able to make a copy and then work on it.

Later this code will be studied how to fix it best.

TComponent removed from most classes.

Notification functionality of TComponent removed from classes. (If this causes bugs or problems remains to be seen, another solution may be used to notify later on, if necessary)

(Grid functionality currently disabled, can be easily fixed in PageControlChange like in simplified version repository)

