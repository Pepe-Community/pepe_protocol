const PepeToken = artifacts.require("PepeToken");
const Utils = artifacts.require("Utils");
const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function (deployer) {
  await deployer.deploy(Utils);
  await deployer.link(Utils, PepeToken);
  const proxyAddress = "0xd6d12B3f2209FD57FD4bFf9a18A4884831D54B09";
  await upgradeProxy(proxyAddress, PepeToken, {
    deployer,
    unsafeAllow: ["external-library-linking"],
  });
};
