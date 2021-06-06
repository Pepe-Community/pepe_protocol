# Deploy PEPE

1. Deploy contract bằng lệnh 

```bash
yarn deploy-contract // Deploy in testnet
yarn deploy-contract:mainnet // Deploy in mainnet
```

2. Sau khi deploy sẽ có 3 contract và 1 library (Utils) được deploy

3. Verify & Publish contract của PepeToken để hiển thị được Proxy contract. Chạy lệnh

```bash

yarn flatten PepeToken
```

để flatten contract Pepe 

4. Verify contract trên BSCScan với các options

```bash
- Compiler version: 0.6.8
- Optimization: Yes
- Lisence: Unlisence
```

![Deploy%20PEPE%207988c26985af49639c351206fe048c08/Untitled.png](Deploy%20PEPE%207988c26985af49639c351206fe048c08/Untitled.png)

Lưu ý: Do contract này sử dụng library nên cần khai báo Library và địa chỉ của Library để verify

![Deploy%20PEPE%207988c26985af49639c351206fe048c08/Untitled%201.png](Deploy%20PEPE%207988c26985af49639c351206fe048c08/Untitled%201.png)

@Ngoc Tam Nguyen em bổ sung cách upgrade và các bước settings ban đầu luôn nhé

# Upgrade PEPE

1. Chỉnh sửa ProxyAddress bằng địa chỉ của TransparentUpgradeProxy

![Deploy%20PEPE%207988c26985af49639c351206fe048c08/Untitled%202.png](Deploy%20PEPE%207988c26985af49639c351206fe048c08/Untitled%202.png)

2. Upgrade contract bằng lệnh

```bash
yarn upgrade-contract // Upgrade in testnet
yarn upgrade-contract:mainnet // Upgrade in mainnet
```

3. Làm lại các bước 2,3,4 như trên để Verify contract