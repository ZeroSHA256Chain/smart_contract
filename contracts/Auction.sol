// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctionHouse {
    using SafeERC20 for IERC20;

    enum AuctionStatus { Active, Ended, Declined, WaitFinalization }
    enum AssetType { Real, ERC20, ERC721, ERC1155 }

    struct RealAsset {
        address arbiter;
        mapping(address => mapping(address => bool)) swapArbiterApproves;
        mapping(address => bool) approves;
    }

    struct ERC20Asset {
        uint256 amount;
        IERC20 tokenContract;
    }

    struct ERC721Asset {
        uint256 id;
        IERC721 tokenContract;
    }

    struct ERC1155Asset {
        uint256 id;
        uint256 amount;
        IERC1155 tokenContract;
    }

    struct Bid {
        uint256 id;
        address sender;
        uint256 price;
        uint256 date;
    }

    struct Asset {
        AssetType kind;
        RealAsset real;
        ERC20Asset erc20;
        ERC721Asset erc721;
        ERC1155Asset erc1155;
    }

    struct Auction {
        string title;
        address creator;
        uint256 bidsCount;
        uint256 endTime;
        uint256 startPrice;
        uint256 bidStep;
        Bid bestBid;
        Asset asset;
        AuctionStatus status;
    }

    struct SavedToken {
        uint256 id;
        AssetType assetType;
        address contractAddress;
        uint256 tokenId;
        uint256 amount;
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Bid[]) public bids;
    mapping(address => SavedToken[]) private _savedTokens;

    uint256 public auctionCount;
    uint256 private savedTokensCount;

    event AuctionCreated(uint256 indexed auctionId, address creator);
    event BidPlaced(uint256 indexed auctionId, address bidder, uint256 amount);
    event AuctionFinalized(uint256 indexed auctionId, address winner, uint256 finalPrice);
    event ArbiterSet(uint256 indexed auctionId, address arbiter);
    event NewSwapArbiterRequest(uint256 indexed auctionId, address arbiter);

    modifier onlyCreator(uint256 auctionId) {
        require(msg.sender == auctions[auctionId].creator, "Not auction creator");
        _;
    }

    modifier onlyExpired(uint256 auctionId) {
        require(auctions[auctionId].endTime < block.timestamp, "Auction not expired");
        _;
    }

    modifier onlyWaitFinalization(uint256 auctionId) {
        require(auctions[auctionId].status != AuctionStatus.WaitFinalization, "Auction not wait finalization");
        _;
    }

    modifier onlyActive(uint256 auctionId) {
        require(auctions[auctionId].status == AuctionStatus.Active, "Auction not active");
        require(auctions[auctionId].endTime > block.timestamp, "Auction expired");
        _;
    }

   modifier haveBids(uint256 auctionId) {
        require(auctions[auctionId].bidsCount > 0, "Auction has no bids");
        _;
    }

    modifier validateAddress(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    function verifyNewArbiter(
        uint256 auctionId, address newArbiter)
    external validateAddress(newArbiter) onlyExpired(auctionId) onlyWaitFinalization(auctionId) haveBids(auctionId) {
        Auction auction = auctions[auctionId];
        require(auction.asset.kind == AssetType.Real, "Invalid asset type");

        RealAsset asset = auction.asset.real;
        asset.swapArbiterApproves[msg.sender][newArbiter] = true;
        if (asset.swapArbiterApproves[auction.creator][newArbiter]
            && asset.swapArbiterApproves[auction.bestBid.sender][newArbiter]) {
            _setArbiter(auctionId, newArbiter);
        } else {
            emit NewSwapArbiterRequest(auctionId, newArbiter);
        }
    }

    function _setArbiter(uint256 auctionId, address newArbiter) internal validateAddress(newArbiter) {
        auctions[auctionId].asset.real.arbiter = newArbiter;
        delete auctions[auctionId].asset.real.swapArbiterApproves; // TODO: Check
        emit ArbiterSet(auctionId, newArbiter);
    }

    function createAuction(
        string memory title,
        AssetType assetType,
        uint256 startPrice,
        uint256 bidStep,
        uint256 endTime,
        address assetContract,
        uint256 assetId,
        uint256 assetAmount,
        address arbiter
    ) external payable {
        require(16 > bytes(title).length > 0, "Title length must be greater than 0 and less than 16");
        require(startPrice > 0 && bidStep > 0, "Start bid and bid step must be greater than zero");
        require(endTime > block.timestamp, "End time must be valid");

        auctionCount++;
        Auction storage auction = auctions[auctionCount];
        auction.creator = msg.sender;
        auction.title = title;
        auction.endTime = endTime;
        auction.startPrice = startPrice;
        auction.bidStep = bidStep;
        auction.status = AuctionStatus.Active;

        setAuctionAsset(auction, assetType, assetContract, assetId, assetAmount, arbiter);

        emit AuctionCreated(auctionCount, msg.sender);
    }

    function setAuctionAsset(
        Auction storage auction,
        AssetType assetType,
        address assetContract,
        uint256 assetId,
        uint256 assetAmount,
        address arbiter
    ) internal {
        if (assetType == AssetType.Real) {
            setRealAsset(auction, arbiter);
        } else if (assetType == AssetType.ERC20) {
            setERC20Asset(auction, assetContract, assetAmount);
        } else if (assetType == AssetType.ERC721) {
            setERC721Asset(auction, assetContract, assetId);
        } else if (assetType == AssetType.ERC1155) {
            setERC1155Asset(auction, assetContract, assetId, assetAmount);
        } else {
            revert("Invalid asset type");
        }
    }

    function setRealAsset(Auction storage auction, address arbiter) internal validateAddress(arbiter) {
        auction.asset.kind = AssetType.Real;
        auction.asset.real.arbiter = arbiter;
    }

    function setERC20Asset(
        Auction storage auction, address assetContract, uint256 assetAmount
    ) internal {
        require(assetAmount > 0, "Invalid ERC20 amount");
        savedTokensCount++;
        IERC20 token = IERC20(assetContract);
        token.safeTransferFrom(msg.sender, address(this), assetAmount);
        auction.asset.kind = AssetType.ERC20;
        auction.asset.erc20 = ERC20Asset(assetAmount, token);
        _savedTokens[msg.sender].push(SavedToken(
            savedTokensCount,
            AssetType.ERC20,
            assetContract,
            0,
            0
        ));
    }

    function setERC721Asset(
        Auction storage auction, address assetContract, uint256 assetId
    ) internal validateAddress(assetContract) {
        savedTokensCount++;
        IERC721 token = IERC721(assetContract);
        token.transferFrom(msg.sender, address(this), assetId);
        auction.asset.kind = AssetType.ERC721;
        auction.asset.erc721 = ERC721Asset(assetId, token);
        _savedTokens[msg.sender].push(SavedToken(
            savedTokensCount,
            AssetType.ERC721,
            assetContract,
            assetId,
            0
        ));
    }

    function setERC1155Asset(
        Auction storage auction, address assetContract, uint256 assetId, uint256 assetAmount
    ) internal validateAddress(assetContract) {
        require(assetAmount > 0, "Invalid ERC1155 amount");
        savedTokensCount++;
        IERC1155 token = IERC1155(assetContract);
        token.safeTransferFrom(msg.sender, address(this), assetId, assetAmount, "");
        auction.asset.kind = AssetType.ERC1155;
        auction.asset.erc1155 = ERC1155Asset(assetId, assetAmount, token);
        _savedTokens[msg.sender].push(SavedToken(
            savedTokensCount,
            AssetType.ERC1155,
            assetContract,
            assetId,
            assetAmount
        ));
    }

    function placeBid(uint256 auctionId) external payable onlyActive(auctionId) {
        require(msg.sender != auctions[auctionId].creator, "Creator cant place bids");

        Bid bestBid = auctions[auctionId].bestBid;
        uint256 baseBid = bestBid.price + auctions[auctionId].bidStep;
        uint256 fivePercent = baseBid * 5 / 100; // 5% fee
        uint256 nextBidAmount = baseBid + fivePercent;

        require(msg.sender != bestBid.sender, "You already place best bid");
        require(msg.value >= nextBidAmount, "Insufficient amount");

        savedTokensCount++;
        auctions[auctionId].bidsCount++;

        Bid newBestBid = Bid(auctions[auctionId].bidsCount, msg.sender, msg.value);
        auctions[auctionId].bestBid = newBestBid;
        bids[auctionId].push(newBestBid);

        _savedTokens[msg.sender].push(
            SavedToken(
                savedTokensCount,
                AssetType.ERC20,
                address(0),
                0,
                baseBid
            )
        );

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }
}
