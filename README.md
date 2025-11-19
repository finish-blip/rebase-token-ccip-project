Rebase Token 需要自定义 TokenPool 的原因是：
在跨链转移 Token 时必须传递用户个体利率（interestRate），否则利息机制会断链，导致用户资产不一致。
✔ 在源链
Lock/Burn token
读取用户利率
跨链发送利率

✔ 在目标链
解码利率
Mint token 给用户
继续用同一个利率计算利息增长

保证用户资产在所有链上的利息保持连续一致。

跨链时用户的个人利率（interestRate）必须带过去，不随链的 APR 变化。

不能跨链带已获得的利息，因为这会导致套利攻击。

每条链上的 APR（系统利率）是独立的，不会跨链传递。

单独测试的命令：
forge test --match-test testCannotCallMintAndBurn -vvv