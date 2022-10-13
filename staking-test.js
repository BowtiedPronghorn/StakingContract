const {
    time,
    expectRevert,
} = require('@openzeppelin/test-helpers');
const Staking = artifacts.require("Staking");
var ERC20PresetFixedSupply = artifacts.require("ERC20PresetFixedSupply");

contract("Token", accounts => {
    const owner = accounts[0];
    const staker1 = accounts[1];
    const staker2 = accounts[2];

    it("Should initialise properly", async () => {
        const stakingToken = await ERC20PresetFixedSupply.new("Pickle", "PICK", 1000000, owner);
        const stakingContract = await Staking.new(stakingToken.address, {from: owner});

        assert.equal(await stakingContract._owner(), owner);
        assert.equal(await stakingContract._stakingtoken(), stakingToken.address);
    });

    // Funding the contract
    it("Should be fundable", async () => {
        let duration = 10;
        let rewardAmount = 1000000;
        const stakingToken = await ERC20PresetFixedSupply.new("Pickle", "PICK", 1000000, owner);
        const rewardToken = await ERC20PresetFixedSupply.new("Rick", "RICK", rewardAmount, owner);
        const stakingContract = await Staking.new(stakingToken.address, {from: owner});

        await rewardToken.approve(stakingContract.address, rewardAmount, {from: owner});
        await stakingContract.fund(rewardToken.address, rewardAmount, duration, {from: owner});
        let block = await web3.eth.getBlock("latest")

        assert.equal(await rewardToken.balanceOf(stakingContract.address), 1000000, "Contract does not get funded with tokens");
        assert.equal(await stakingContract._rewardrate(), rewardAmount / duration, "Reward rate not calculated properly");
        assert.equal(await stakingContract._endrewards(), block.number + duration, "Rewards end time not set correctly");
    });

    // Staking tokens in the contract
    it("Should be possible for users to stake tokens", async () => {
        let duration = 10;
        let rewardAmount = 1000000;
        let supply = 1000000;
        let balance = supply /2;

        // initialise tokens
        const stakingToken = await ERC20PresetFixedSupply.new("Pickle", "PICK", supply, owner);
        const rewardToken = await ERC20PresetFixedSupply.new("Rick", "RICK", supply, owner);
        await stakingToken.transfer(staker1, balance), {from: owner};
        await stakingToken.transfer(staker2, balance), {from: owner};

        // initialise contract
        const stakingContract = await Staking.new(stakingToken.address, {from: owner});
        await rewardToken.approve(stakingContract.address, rewardAmount, {from: owner});
        await stakingContract.fund(rewardToken.address, rewardAmount, duration, {from: owner});

        // stake tokens
        await stakingToken.approve(stakingContract.address, supply/2, {from: staker1});
        await stakingContract.stake(balance, {from: staker1});
        assert.equal(await stakingToken.balanceOf(staker1), 0, "staker1 shouldn't have balance after staking");
        assert.equal(await stakingToken.balanceOf(stakingContract.address), balance, "Contract should contain tokens after staking");

        // check that staking registers the deposit properly
        let block = await web3.eth.getBlock("latest");
        let _blocknum = await stakingContract.getUserDepositTime(staker1);
        let _depositamount = await stakingContract.getUserDepositAmount(staker1);
        assert.equal(_blocknum, block.number, "Contract does not register deposited bluck number correctly");
        assert.equal(_depositamount, balance, "Contract does not update balance properly");
    });

    // Withdrawing tokens from the contract
    it("Should be possible for users to withdraw their tokens", async () => {
        let duration = 10;
        let rewardAmount = 1000000;
        let supply = 1000000;
        let balance = supply /2;

        // initialise tokens
        const stakingToken = await ERC20PresetFixedSupply.new("Pickle", "PICK", supply, owner);
        const rewardToken = await ERC20PresetFixedSupply.new("Rick", "RICK", supply, owner);
        await stakingToken.transfer(staker1, balance), {from: owner};
        await stakingToken.transfer(staker2, balance), {from: owner};

        // initialise contract
        const stakingContract = await Staking.new(stakingToken.address, {from: owner});
        await rewardToken.approve(stakingContract.address, rewardAmount, {from: owner});
        await stakingContract.fund(rewardToken.address, rewardAmount, duration, {from: owner});

        // stake tokens
        await stakingToken.approve(stakingContract.address, supply/2, {from: staker1});
        await stakingContract.stake(balance, {from: staker1});

        // withdraw half of tokens
        await stakingContract.withdraw(10, {from: staker1});
        await stakingContract.withdraw(10, {from: staker1});
        await stakingContract.withdraw(10, {from: staker1});

        // withdraw more tokens than should be possible
        await expectRevert(stakingContract.withdraw(balance, {from: staker1}),
            "Cannot withdraw more tokens than you deposited");

        await stakingContract.withdraw(balance-30, {from: staker1});
        assert.equal(await stakingToken.balanceOf(staker1), balance);
    });

    // Claiming reward tokens from contract
    it("Should be possible for users to claim their reward tokens", async () => {
        let duration = 10;
        let rewardAmount = 1000000;
        let supply = 1000000;
        let balance = supply /2;

        // initialise tokens
        const stakingToken = await ERC20PresetFixedSupply.new("Pickle", "PICK", supply, owner);
        const rewardToken = await ERC20PresetFixedSupply.new("Rick", "RICK", supply, owner);
        await stakingToken.transfer(staker1, balance), {from: owner};
        await stakingToken.transfer(staker2, balance), {from: owner};

        // initialise contract
        const stakingContract = await Staking.new(stakingToken.address, {from: owner});
        await rewardToken.approve(stakingContract.address, rewardAmount, {from: owner});
        await stakingContract.fund(rewardToken.address, rewardAmount, duration, {from: owner});

        // stake tokens
        await stakingToken.approve(stakingContract.address, balance, {from: staker1});
        await stakingContract.stake(balance, {from: staker1});

        // advance three blocks
        await time.advanceBlock();
        await time.advanceBlock();
        await time.advanceBlock();

        // check that claiming tokens works
        await stakingContract.claim({from: staker1});
        assert.equal(await rewardToken.balanceOf(staker1), rewardAmount / 10 * 3);
    });
});