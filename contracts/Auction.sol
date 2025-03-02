// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AuctionHouse is Ownable {
    using SafeERC20 for IERC20;

    enum AuctionStatus { Active, Finalized, Refunded, WaitFinalization }
    enum AssetType { Real, ERC20, ERC721, ERC1155 }

    struct RealAsset {
        address arbiter;
        mapping(address => mapping(address => bool)) swapArbiterApproves;
        mapping(address => bool) approves;
        mapping(address => bool) refundRequests;
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
        bool withdrawn;
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
        AssetType assetType;
        address contractAddress;
        uint256 tokenId;
        uint256 amount;
        bool withdrawn;
    }

    struct RealAssetView {
        address arbiter;
    }

    struct AssetView {
        AssetType kind;
        RealAssetView real;
        ERC20Asset erc20;
        ERC721Asset erc721;
        ERC1155Asset erc1155;
    }

    struct AuctionView {
        string title;
        address creator;
        uint256 bidsCount;
        uint256 endTime;
        uint256 startPrice;
        uint256 bidStep;
        Bid bestBid;
        AssetView asset;
        AuctionStatus status;
    }

    mapping(uint256 => Auction) private auctions;
    mapping(uint256 => Bid[]) public bids;
    mapping(address => mapping(uint256 => SavedToken)) private _savedTokens;

    uint256 public auctionCount;
    uint256 private fees;
    uint256 public feeRate;

    event AuctionCreated(uint256 indexed auctionId, address creator);
    event AuctionFinalized(uint256 indexed auctionId, address winner, uint256 finalPrice);
    event AuctionRefunded(uint256 indexed auctionId, address bidder, uint256 refundedAmount);
    event ArbiterSet(uint256 indexed auctionId, address arbiter);
    event NewArbiterRequest(uint256 indexed auctionId, address arbiter);
    event BidPlaced(uint256 indexed auctionId, uint256 bidId, address bidder, uint256 amount);
    event BidWithdrawn(uint256 indexed auctionId, uint256 bidId, address bidder, uint256 amount);
    event WithdrawAssets(uint256 indexed auctionId, address to, uint256 amount, uint256 assetId);

    constructor(uint256 _fee) Ownable(msg.sender) {
        require(_fee <= 100 && _fee >= 1, "Fee must be between 1 and 100");
        feeRate = _fee;
    }

    function changeOwner(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
    }

   function calcFee(uint256 amount) public view returns (uint256) {
        return (amount * feeRate) / 100;
    }

    function withdrawFees() external onlyOwner {
        require(fees > 0, "Empty fees balance");
        payable(owner()).transfer(fees);
        fees = 0;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    modifier onlyCreator(uint256 auctionId) {
        require(msg.sender == auctions[auctionId].creator, "Not auction creator");
        _;
    }

   modifier onlyNonCreator(uint256 auctionId) {
        require(msg.sender != auctions[auctionId].creator, "As creator you can't do this");
        _;
    }

    modifier onlyExpired(uint256 auctionId) {
        require(auctions[auctionId].endTime < block.timestamp, "Auction not expired");
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

    modifier onlyDealActors(uint256 auctionId) {
        require(
            msg.sender != address(0) &&
            (msg.sender == auctions[auctionId].creator ||
             msg.sender == auctions[auctionId].bestBid.sender ||
             msg.sender == auctions[auctionId].asset.real.arbiter),
            "You can't call this"
        );
        _;
    }

    modifier notWithdrawn(uint256 auctionId) {
        require(!auctions[auctionId].bestBid.withdrawn, "Bid already have been withdrawn");
        _;
    }

    function getAuction(uint256 auctionId) public view returns (AuctionView memory){
        return AuctionView(
            auctions[auctionId].title,
            auctions[auctionId].creator,
            auctions[auctionId].bidsCount,
            auctions[auctionId].endTime,
            auctions[auctionId].startPrice,
            auctions[auctionId].bidStep,
            auctions[auctionId].bestBid,
            AssetView(
                auctions[auctionId].asset.kind,
                RealAssetView(
                    auctions[auctionId].asset.real.arbiter
                ),
                auctions[auctionId].asset.erc20,
                auctions[auctionId].asset.erc721,
                auctions[auctionId].asset.erc1155
            ),
            auctions[auctionId].status
        );
    }

    function verifyNewArbiter(
        uint256 auctionId, address newArbiter
    ) external validateAddress(newArbiter) onlyExpired(auctionId) onlyDealActors(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.asset.kind == AssetType.Real, "Invalid asset type");
        RealAsset storage asset = auction.asset.real;
        require(msg.sender != asset.arbiter, "Arbiter cant call this");
        require(newArbiter != asset.arbiter, "The same arbiter provided");
        require(newArbiter != auction.creator, "Arbiter and creator cant be the same");
        require(newArbiter != auction.bestBid.sender, "Arbiter and bestBidder cant be the same");

        asset.swapArbiterApproves[msg.sender][newArbiter] = true;
        if (asset.swapArbiterApproves[auction.creator][newArbiter]
            && asset.swapArbiterApproves[auction.bestBid.sender][newArbiter]) {
            _setArbiter(auctionId, newArbiter);
        } else {
            emit NewArbiterRequest(auctionId, newArbiter);
        }
    }

    function _setArbiter(uint256 auctionId, address newArbiter) internal validateAddress(newArbiter) {
        delete auctions[auctionId].asset.real; // TODO: Check
        auctions[auctionId].asset.real.arbiter = newArbiter;
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
    ) public payable {
        require(
            bytes(title).length > 0 && bytes(title).length < 16,
            "Title length must be greater than 0 and less than 16"
        );
        require(startPrice > 0 && bidStep > 0, "Start bid and bid step must be greater than zero");
        require(endTime > block.timestamp, "End time must be valid");
        require(arbiter != msg.sender, "Arbiter and creator cant be the same");

        auctionCount++;
        Auction storage auction = auctions[auctionCount];
        auction.creator = msg.sender;
        auction.title = title;
        auction.endTime = endTime;
        auction.startPrice = startPrice;
        auction.bidStep = bidStep;
        auction.status = AuctionStatus.Active;

        setAuctionAsset(
            auction, assetType, assetContract, assetId, assetAmount, arbiter
        );

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
        uint256 fee = calcFee(assetAmount);
        if (assetContract == address(0)) {
            require(assetAmount == msg.value, "Invalid ETH amount");
            auction.asset.erc20.amount = assetAmount - fee;
        } else {
            IERC20 token = IERC20(assetContract);
            token.safeTransferFrom(msg.sender, address(this), assetAmount);
            auction.asset.erc20 = ERC20Asset(assetAmount - fee, token);
        }

        fees += fee;
        auction.asset.kind = AssetType.ERC20;
        _savedTokens[msg.sender][auctionCount] = SavedToken(
            AssetType.ERC20,
            assetContract,
            0,
            auction.asset.erc20.amount,
            false
        );
    }

    function setERC721Asset(
        Auction storage auction, address assetContract, uint256 assetId
    ) internal validateAddress(assetContract) {
        IERC721 token = IERC721(assetContract);
        require(assetId > 0, "Invalid assetId");
        if (token.getApproved(assetId) != address(this)) {
          revert("ERC721: insufficient approval");
        }
        token.transferFrom(msg.sender, address(this), assetId);
        auction.asset.kind = AssetType.ERC721;
        auction.asset.erc721 = ERC721Asset(assetId, token);
        _savedTokens[msg.sender][auctionCount] = SavedToken(
            AssetType.ERC721,
            assetContract,
            assetId,
            0,
            false
        );
    }

    function setERC1155Asset(
        Auction storage auction, address assetContract, uint256 assetId, uint256 assetAmount
    ) internal validateAddress(assetContract) {
        require(assetAmount > 0, "Invalid ERC1155 amount");
        require(assetId > 0, "Invalid assetId");
        IERC1155 token = IERC1155(assetContract);
        token.safeTransferFrom(msg.sender, address(this), assetId, assetAmount, "");
        auction.asset.kind = AssetType.ERC1155;
        auction.asset.erc1155 = ERC1155Asset(assetId, assetAmount, token);
        _savedTokens[msg.sender][auctionCount] = SavedToken(
            AssetType.ERC1155,
            assetContract,
            assetId,
            assetAmount,
            false
        );
    }

    function placeBid(uint256 auctionId) external payable onlyNonCreator(auctionId) onlyActive(auctionId) {
        require(msg.sender != auctions[auctionId].bestBid.sender, "You already place best bid");
        require(msg.sender != auctions[auctionId].asset.real.arbiter, "Arbiter cant place bids");

        uint256 nextBidAmount = auctions[auctionId].startPrice;
        if (auctions[auctionId].bestBid.price != 0) {
            nextBidAmount = auctions[auctionId].bestBid.price + auctions[auctionId].bidStep;
        }

        uint256 amount = msg.value;
        uint256 fee = calcFee(msg.value);
        amount -= fee;

        require(amount >= nextBidAmount, "Invalid bid amount");

        auctions[auctionId].bidsCount++;

        fees += fee;
        Bid memory newBestBid = Bid(
            auctions[auctionId].bidsCount, msg.sender, amount, block.timestamp, false
        );
        auctions[auctionId].bestBid = newBestBid;
        bids[auctionId].push(newBestBid);

        _savedTokens[msg.sender][auctionCount] = SavedToken(
            AssetType.ERC20,
            address(0),
            0,
            amount,
            false
        );

        emit BidPlaced(auctionId, auctions[auctionId].bidsCount, msg.sender, amount);
    }

    function takeMyBid(uint256 auctionId, uint256 bidId) external onlyNonCreator(auctionId) {
        require(auctions[auctionId].bidsCount >= bidId, "Invalid bid id");
        require(
            bids[auctionId][bidId].sender == msg.sender,
            "You cannot withdraw tokens that are not yours"
        );
        require(
            !bids[auctionId][bidId].withdrawn,
            "Tokens have been already withdrawn"
        );
        require(
            auctions[auctionId].bestBid.id != bidId
            || block.timestamp - auctions[auctionId].endTime >= 86400 * 3,
            "You cant take actual bid"
        );

        payable(msg.sender).transfer(bids[auctionId][bidId].price);
        bids[auctionId][bidId].withdrawn = true;

        emit BidWithdrawn(auctionId, bidId, msg.sender, bids[auctionId][bidId].price);
    }

    function requestWithdraw(uint256 auctionId) external onlyDealActors(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.endTime, "Auction not yet ended");
        require(
            auction.status == AuctionStatus.Active
            || auction.status == AuctionStatus.WaitFinalization
            || auction.status == AuctionStatus.Refunded,
            "Auction already finalized"
        );

        if (auction.bestBid.sender == address(0)) {
            _withdrawToken(auctionId, auction.creator);
            return;
        }

        if (auction.status == AuctionStatus.Refunded) {
            require(msg.sender == auction.creator, "Only creator can withdraw if refunded");
            _withdrawToken(auctionId, auction.creator);
            return;
        }

        _finalizeAuction(auction, auctionId);
    }

    function _finalizeAuction(Auction storage auction, uint256 auctionId) internal {
        auction.status = AuctionStatus.WaitFinalization;
        if (auction.asset.kind != AssetType.Real) {
            _finalizeDigitalAsset(auction, auctionId);
        } else {
            _finalizeRealAsset(auction, auctionId);
        }
    }

    function _finalizeDigitalAsset(Auction storage auction, uint256 auctionId) internal onlyDealActors(auctionId) {
        if (msg.sender == auction.creator) {
            require(!auction.bestBid.withdrawn, "Bid already have been withdrawn");
            payable(auction.creator).transfer(auction.bestBid.price);
        } else {
            _withdrawToken(auctionId, auction.bestBid.sender);
        }
        if (auction.bestBid.withdrawn && _savedTokens[auction.creator][auctionId].withdrawn) {
            auction.status = AuctionStatus.Finalized;
            emit AuctionFinalized(
                auctionId, auction.bestBid.sender, auction.bestBid.price
            );
        }
    }


    function _finalizeRealAsset(
        Auction storage auction, uint256 auctionId
    ) internal notWithdrawn(auctionId) onlyDealActors(auctionId) {
        auction.asset.real.approves[msg.sender] = true;

        uint approvalCount = 0;
        if (auction.asset.real.approves[auction.creator]) approvalCount++;
        if (auction.asset.real.approves[auction.bestBid.sender]) approvalCount++;
        if (auction.asset.real.approves[auction.asset.real.arbiter]) approvalCount++;

        if (approvalCount >= 2 && msg.sender == auction.creator) {
            payable(auction.creator).transfer(auction.bestBid.price);
            auction.status = AuctionStatus.Finalized;
            emit AuctionFinalized(
                auctionId, auction.bestBid.sender, auction.bestBid.price
            );
        }
    }

    function approveRefund(
        uint256 auctionId
    ) public onlyExpired(auctionId) haveBids(auctionId) onlyDealActors(auctionId) notWithdrawn(auctionId) {
        Auction storage auction = auctions[auctionId];
        auction.asset.real.refundRequests[msg.sender] = true;

        uint approvalCount = 0;
        if (auction.asset.real.refundRequests[auction.creator]) approvalCount++;
        if (auction.asset.real.refundRequests[auction.bestBid.sender]) approvalCount++;
        if (auction.asset.real.refundRequests[auction.asset.real.arbiter]) approvalCount++;

        if (approvalCount >= 2 && msg.sender == auction.bestBid.sender) {
            payable(auction.bestBid.sender).transfer(auction.bestBid.price);
            auction.status = AuctionStatus.Refunded;
            emit AuctionRefunded(
                auctionId, auction.bestBid.sender, auction.bestBid.price
            );
        }
    }

    function _withdrawToken(uint256 auctionId, address to) internal {
        require(auctionCount >= auctionId, "Invalid auction id");

        AssetType assetType = auctions[auctionId].asset.kind;
        require(assetType != AssetType.Real, "Asset with this type dont support withdraw");

        if (assetType == AssetType.ERC20) {
            _withdrawERC20Asset(auctionId, to);
        } else if (assetType == AssetType.ERC721) {
            _withdrawERC721Asset(auctionId, to);
        } else if (assetType == AssetType.ERC1155) {
            _withdrawERC1155Asset(auctionId, to);
        }
    }

    function _withdrawERC20Asset(uint256 auctionId, address to) internal {
        require(auctions[auctionId].asset.kind == AssetType.ERC20, "Not an ERC20 asset");

        ERC20Asset storage erc20Asset = auctions[auctionId].asset.erc20;
        require(
            !_savedTokens[auctions[auctionId].creator][auctionId].withdrawn
            && erc20Asset.amount > 0,
            "No ERC20 asset to withdraw"
        );

        if (address(erc20Asset.tokenContract) == address(0)) {
            payable(to).transfer(erc20Asset.amount);
        } else {
            IERC20 token = IERC20(erc20Asset.tokenContract);
            token.safeTransfer(to, erc20Asset.amount);
        }

        _savedTokens[auctions[auctionId].creator][auctionId].withdrawn = true;

        emit WithdrawAssets(auctionId, to, erc20Asset.amount, 0);
    }

    function _withdrawERC721Asset(uint256 auctionId, address to) internal {
        require(auctions[auctionId].asset.kind == AssetType.ERC721, "Not an ERC721 asset");
        require(
            !_savedTokens[auctions[auctionId].creator][auctionId].withdrawn,
            "Token has been already withdrawn"
        );

        ERC721Asset memory erc721Asset = auctions[auctionId].asset.erc721;
        IERC721 token = IERC721(erc721Asset.tokenContract);
        token.transferFrom(address(this), to, erc721Asset.id);

        _savedTokens[auctions[auctionId].creator][auctionId].withdrawn = true;

        emit WithdrawAssets(auctionId, to, 0, erc721Asset.id);
    }

    function _withdrawERC1155Asset(uint256 auctionId, address to) internal {
        require(auctions[auctionId].asset.kind == AssetType.ERC1155, "Not an ERC1155 asset");

        ERC1155Asset memory erc1155Asset = auctions[auctionId].asset.erc1155;
        require(
            !_savedTokens[auctions[auctionId].creator][auctionId].withdrawn
            && erc1155Asset.amount > 0,
            "No ERC1155 asset to withdraw"
        );

        IERC1155 token = IERC1155(erc1155Asset.tokenContract);
        token.safeTransferFrom(address(this), to, erc1155Asset.id, erc1155Asset.amount, "");

        _savedTokens[auctions[auctionId].creator][auctionId].withdrawn = true;

        emit WithdrawAssets(auctionId, to, erc1155Asset.amount, erc1155Asset.id);
    }
}
