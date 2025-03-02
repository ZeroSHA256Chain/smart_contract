const { expect } = require("chai");
const { time, loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ethers } = require("hardhat");

const AuctionStatus = {
    Active: 0,
    Finalized: 1,
    Refunded: 2,
    WaitFinalization: 3
};

const AssetType = {
    Real: 0,
    ERC20: 1,
    ERC721: 2,
    ERC1155: 3
};

function calcFee(amountInEth) {
    const amountInWei = ethers.parseEther(amountInEth.toString());
    const feeInWei = amountInWei - (amountInWei * BigInt(5)) / BigInt(100);
    return feeInWei;
}

describe("AuctionHouse", function () {
     async function deploy() {
        [ owner, creator, arbiter, newArbiter, bestBidder, bidder1, bidder2, bidder3 ] = await ethers.getSigners();
        const expired_at = (await time.latest()) + 86400 * 7; // 7 days later
        const Auction = await ethers.getContractFactory("AuctionHouse");
        const contract = await Auction.deploy(BigInt(5));
        const auctionTitle = "MyCoolAuction";
        const oneEther = ethers.parseEther("1");
      
        const ERC20 = await ethers.getContractFactory("ERC20Mock");
        ERC20Mock = await ERC20.deploy();
        await ERC20Mock.transfer(creator, oneEther);

        const ERC721 = await ethers.getContractFactory("ERC721Mock");
        ERC721Mock = await ERC721.deploy();
        await ERC721Mock.mint(creator);

        const ERC1155 = await ethers.getContractFactory("ERC1155Mock");
        ERC1155Mock = await ERC1155.deploy();
        await ERC1155Mock.mint(creator, 1, 100)

        return { 
          contract, expired_at, owner, creator, arbiter, newArbiter, bestBidder, bidder1, bidder2, bidder3, auctionTitle, oneEther, };
    }

    describe("Auction Creation", function () {
      describe("Common Reverts", function () {
        it("Should revert creation auction if invalid name length", async function () {
            const { contract, expired_at, arbiter, oneEther } =  await loadFixture(deploy);
            await expect(contract.connect(creator).createAuction(
                "",
                AssetType.Real,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ethers.ZeroAddress,
                0,
                0,
                arbiter,
            )).to.be.revertedWith("Title length must be greater than 0 and less than 16");

            await expect(contract.connect(creator).createAuction(
                "133722889012345678901234567890",
                AssetType.Real,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ethers.ZeroAddress,
                0,
                0,
                arbiter,
            )).to.be.revertedWith("Title length must be greater than 0 and less than 16");
        });

        it("Should revert creation auction if bad initial bids", async function () {
            const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.Real,
                ethers.parseEther("0"),
                ethers.parseEther("0.1"),
                expired_at,
                ethers.ZeroAddress,
                0,
                0,
                arbiter,
            )).to.be.revertedWith("Start bid and bid step must be greater than zero");

            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.Real,
                oneEther,
                ethers.parseEther("0"),
                expired_at,
                ethers.ZeroAddress,
                0,
                0,
                arbiter,
            )).to.be.revertedWith("Start bid and bid step must be greater than zero");
          });

        it("Should revert creation auction if bad end time provided", async function () {
            const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.Real,
                oneEther,
                ethers.parseEther("0.1"),
                0,
                ethers.ZeroAddress,
                0,
                0,
                arbiter,
            )).to.be.revertedWith("End time must be valid");
        });
      });

      describe("Common auction creation", function () {
        it("Should create a RealAsset auction", async function () {
            const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.Real,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ethers.ZeroAddress,
                0,
                0,
                arbiter.address,
            )).to.emit(contract, "AuctionCreated")
              .withArgs(1, creator.address);
            const count = await contract.auctionCount();
            const auction = await contract.getAuction(count);
            expect(auction.title).to.equal(auctionTitle);
            expect(auction.asset.kind).to.equal(AssetType.Real);
            expect(auction.asset.real.arbiter).to.equal(arbiter.address);
        });
        
        it("Should create a ETH auction", async function () {
            const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.ERC20,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ethers.ZeroAddress,
                0,
                oneEther,
                ethers.ZeroAddress,
                { value: oneEther },
            )).to.emit(contract, "AuctionCreated")
              .withArgs(1, creator.address);
            
            const count = await contract.auctionCount();
            const auction = await contract.getAuction(count);
            expect(auction.title).to.equal(auctionTitle);
            expect(auction.asset.kind).to.equal(AssetType.ERC20);
            expect(auction.asset.erc20.amount).to.equal(calcFee("1"));
        });

        it("Should create a ERC20 auction", async function () {
            const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
            
            await ERC20Mock.connect(creator).approve(contract, oneEther);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.ERC20,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ERC20Mock,
                0,
                oneEther,
                ethers.ZeroAddress,
                { value: oneEther },
            )).to.emit(contract, "AuctionCreated")
              .withArgs(1, creator.address);
            const count = await contract.auctionCount();
            const auction = await contract.getAuction(count);
            expect(auction.title).to.equal(auctionTitle);
            expect(auction.asset.kind).to.equal(AssetType.ERC20);
            expect(auction.asset.erc20.amount).to.equal(calcFee("1"));
        });

        it("Should create a ERC721 auction", async function () {
            const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
            
            await ERC721Mock.connect(creator).approve(contract, 1);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.ERC721,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ERC721Mock,
                1,
                0,
                ethers.ZeroAddress
            )).to.emit(contract, "AuctionCreated")
              .withArgs(1, creator.address);
            const count = await contract.auctionCount();
            const auction = await contract.getAuction(count);
            expect(auction.title).to.equal(auctionTitle);
            expect(auction.asset.kind).to.equal(AssetType.ERC721);
            expect(auction.asset.erc721.id).to.equal(1);
        });

        it("Should create a ERC1155 auction", async function () {
            const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
            
            await ERC1155Mock.connect(creator).setApprovalForAll(contract, true);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.ERC1155,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ERC1155Mock,
                1,
                50,
                ethers.ZeroAddress
            )).to.emit(contract, "AuctionCreated")
              .withArgs(1, creator.address);
            const count = await contract.auctionCount();
            const auction = await contract.getAuction(count);
            expect(auction.title).to.equal(auctionTitle);
            expect(auction.asset.kind).to.equal(AssetType.ERC1155);
            expect(auction.asset.erc1155.id).to.equal(1);
            expect(auction.asset.erc1155.amount).to.equal(50);
        });
      });
    
      describe("Asset Typed reverts", function () {
        it("Should revert creation RealAsset auction if aribiter is null", async function () {
            const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.Real,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ethers.ZeroAddress,
                0,
                0,
                ethers.ZeroAddress,
            )).to.be.revertedWith("Invalid address");
        });

        it("Should revert creation RealAsset auction if aribiter is creator", async function () {
            const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
            await expect(contract.connect(creator).createAuction(
                auctionTitle,
                AssetType.Real,
                oneEther,
                ethers.parseEther("0.1"),
                expired_at,
                ethers.ZeroAddress,
                0,
                0,
                creator,
            )).to.be.revertedWith("Arbiter and creator cant be the same");
        });

       it("Should revert ETH auction if sended amount and msg.value not equal", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC20,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ethers.ZeroAddress,
              0,
              oneEther,
              ethers.ZeroAddress,
              { value: ethers.parseEther("2") },
            )).to.be.revertedWith("Invalid ETH amount");
      });
      
      it("Should revert ETH auction if sended amount and msg.value not equal", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC20,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ethers.ZeroAddress,
              0,
              oneEther,
              ethers.ZeroAddress,
              { value: ethers.parseEther("2") },
            )).to.be.revertedWith("Invalid ETH amount");
      });

      it("Should revert ERC20 auction if zero amount provided", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC20,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ethers.ZeroAddress,
              0,
              ethers.parseEther("0"),
              ethers.ZeroAddress,
              { value: oneEther },
            )).to.be.revertedWith("Invalid ERC20 amount");
      });

      it("Should revert ERC20 auction if insufficient allowance", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC20,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ERC20Mock,
              0,
              oneEther,
              ethers.ZeroAddress,
              { value: oneEther },
            )).to.be.revertedWithCustomError(ERC20Mock, "ERC20InsufficientAllowance");
      });

      it("Should revert ERC721 auction if insufficient approval", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC721,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ERC721Mock,
              1,
              0,
              ethers.ZeroAddress,
              { value: oneEther },
            )).to.be.revertedWith("ERC721: insufficient approval");
      });

      it("Should revert ERC1155 auction if invalid token id", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC1155,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ERC1155Mock,
              0,
              oneEther,
              ethers.ZeroAddress,
              { value: oneEther },
            )).to.be.revertedWith("Invalid assetId");
      });

      it("Should revert ERC1155 auction if invalid token id", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC1155,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ERC1155Mock,
              1,
              0,
              ethers.ZeroAddress,
              { value: oneEther },
            )).to.be.revertedWith("Invalid ERC1155 amount");
      });

      it("Should revert ERC1155 auction if missing approval", async function () {
          const { contract, expired_at, auctionTitle, oneEther } =  await loadFixture(deploy);
          await expect(contract.connect(creator).createAuction(
              auctionTitle,
              AssetType.ERC1155,
              oneEther,
              ethers.parseEther("0.1"),
              expired_at,
              ERC1155Mock,
              1,
              100,
              ethers.ZeroAddress,
              { value: oneEther },
            )).to.be.revertedWithCustomError(ERC1155Mock, "ERC1155MissingApprovalForAll");
      });
    });
  });
    

  describe("Bids", function () {
    it("Should allow to place a bid", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.Real,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            0,
            arbiter.address,
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);

        await expect(contract.connect(bestBidder).placeBid(1, { value: ethers.parseEther("1.1") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 1, bestBidder, calcFee(1.1));
        
        const project = await contract.getAuction(1);
        const bid = await contract.bids(1, 0);
        expect(bid[2]).to.be.equal(calcFee(1.1));
    });

    it("Should allow to bit a bid", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.Real,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            0,
            arbiter.address,
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);

        await expect(contract.connect(bidder1).placeBid(1, { value: ethers.parseEther("1.1") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 1, bidder1, calcFee(1.1));
        
        await expect(contract.connect(bestBidder).placeBid(1, { value: ethers.parseEther("2") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 2, bestBidder, calcFee(2));
    });

    it("Should allow to withdraw a bid", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.Real,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            0,
            arbiter.address,
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);
        
        await expect(contract.connect(bidder1).placeBid(1, { value: ethers.parseEther("1.1") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 1, bidder1, calcFee(1.1));
        
        await expect(contract.connect(bestBidder).placeBid(1, { value: ethers.parseEther("2") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 2, bestBidder, calcFee(2));
  
        await time.increase(86400 * 8);
        const project = await contract.getAuction(1);
        const bid = await contract.bids(1, 0);
        expect(bid[2]).to.be.equal(calcFee(1.1));
        
        await expect(contract.connect(bidder1).takeMyBid(1, 0))
          .to.emit(contract, "BidWithdrawn")
          .withArgs(1, 0, bidder1, calcFee(1.1));
    });
  });
  

  describe("Refund", function () {
    it("Should allow to refund with 2+ approves", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } = await loadFixture(deploy);
        await ERC20Mock.connect(creator).approve(contract, oneEther);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.ERC20,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            oneEther,
            ethers.ZeroAddress,
            { value: oneEther },
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);

        await time.increase(86400 * 8);
        await contract.connect(creator).requestWithdraw(1);
    });
  });
  
  describe("Withdraws", function () {
    it("Should allow to withdraw tokens to creator", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } = await loadFixture(deploy);
        await ERC20Mock.connect(creator).approve(contract, oneEther);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.ERC20,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            oneEther,
            ethers.ZeroAddress,
            { value: oneEther },
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);

        await expect(contract.connect(bestBidder).placeBid(1, { value: ethers.parseEther("2") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 1, bestBidder, calcFee(2));
        await time.increase(86400 * 8);

        await expect(contract.connect().approveRefund(1))
        await expect(contract.connect(bestBidder).approveRefund(1))
    });

    it("Should allow to withdraw tokens to bidder and creator", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } = await loadFixture(deploy);
        await ERC20Mock.connect(creator).approve(contract, oneEther);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.ERC20,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            oneEther,
            ethers.ZeroAddress,
            { value: oneEther },
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);

        await expect(contract.connect(bestBidder).placeBid(1, { value: ethers.parseEther("2") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 1, bestBidder, calcFee(2));
        await time.increase(86400 * 8);

        // Withdraw assets to bestBidder
        await expect(contract.connect(bestBidder).requestWithdraw(1))
          .to.emit(contract, "WithdrawAssets")
          .withArgs(1, bestBidder, calcFee(1), 0);

        // Withdraw bid amount to creator
        await expect(contract.connect(creator).requestWithdraw(1))
          .to.emit(contract, "AuctionFinalized")
          .withArgs(1, bestBidder, calcFee(2));
    });
  });

  describe("Arbiter changing", function () {
    it("Should allow change arbiter to another one if creator and bestBidder consistent", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.Real,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            0,
            arbiter.address,
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);

        await expect(contract.connect(bestBidder).placeBid(1, { value: ethers.parseEther("1.1") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 1, bestBidder, calcFee(1.1));

        await time.increase(86400 * 8);
        await expect(contract.connect(creator).verifyNewArbiter(1, newArbiter))
          .to.emit(contract, "NewArbiterRequest")
          .withArgs(1, newArbiter);
        await expect(contract.connect(bestBidder).verifyNewArbiter(1, newArbiter))
          .to.emit(contract, "ArbiterSet")
          .withArgs(1, newArbiter);
    });

    it("Should revert change arbiter to the sender, creator, arbiter, bestBidder", async function () {
        const { contract, expired_at, arbiter, auctionTitle, oneEther } =  await loadFixture(deploy);
        await expect(contract.connect(creator).createAuction(
            auctionTitle,
            AssetType.Real,
            oneEther,
            ethers.parseEther("0.1"),
            expired_at,
            ethers.ZeroAddress,
            0,
            0,
            arbiter.address,
        )).to.emit(contract, "AuctionCreated")
          .withArgs(1, creator.address);

        await expect(contract.connect(bestBidder).placeBid(1, { value: ethers.parseEther("1.1") }))
          .to.emit(contract, "BidPlaced")
          .withArgs(1, 1, bestBidder, calcFee(1.1));
        
        await time.increase(86400 * 8);

        await expect(contract.connect(bestBidder).verifyNewArbiter(1, creator))
          .to.be.revertedWith("Arbiter and creator cant be the same");
        await expect(contract.connect(creator).verifyNewArbiter(1, bestBidder))
          .to.revertedWith("Arbiter and bestBidder cant be the same");
        await expect(contract.connect(arbiter).verifyNewArbiter(1, bestBidder))
          .to.revertedWith("Arbiter cant call this");
        await expect(contract.connect(bestBidder).verifyNewArbiter(1, arbiter))
          .to.revertedWith("The same arbiter provided");
    });
  });
});
