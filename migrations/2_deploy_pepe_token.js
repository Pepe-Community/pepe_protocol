const PepeToken = artifacts.require("PepeToken");
const Utils = artifacts.require("Utils");
const { deployProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function (deployer) {
  await deployer.deploy(Utils);
  await deployer.link(Utils, PepeToken);

  let PANCAKE_ROUTER = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

  if (process.env.PANCAKE_ROUTER != undefined){
    PANCAKE_ROUTER = process.env.PANCAKE_ROUTER;
  }

  console.log(`PANCAKE_ROUTER ${PANCAKE_ROUTER}`);

  
  await deployProxy(PepeToken, [PANCAKE_ROUTER], {
    deployer,
    unsafeAllow: ["external-library-linking"],
    initializer: "initialize",
  });
};
