// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

using SafeERC20 for IERC20;

/*
拍卖合约：
实现一个拍卖合约，支持以下功能：
1. 创建拍卖：允许用户将 NFT 上架拍卖。
2. 出价：允许用户以 ERC20 或以太坊出价。
3. 结束拍卖：拍卖结束后，NFT 转移给出价最高者，资金转移给卖家
*/
contract NFTAuction is Initializable, ReentrancyGuard, UUPSUpgradeable {
    struct Auction {
        address seller;
        uint256 duration; // 拍卖持续时间（秒）
        uint256 startTime; // 拍卖开始时间
        uint256 startPrice; // 起始价格
        address startPriceAddress; // 其实价格代币类型 address(0) 表示以太坊
        bool ended; // 拍卖是否结束
        uint256 highestBid; // 最高出价
        address highestBidder; // 最高出价者
        address nftAddress; // NFT 合约地址
        uint256 tokenId; // NFT ID
        address tokenAddress; // 出价使用的代币地址 默认 address(0) 表示以太坊
    }

    mapping(uint256 => Auction) public auctions; // 拍卖ID到拍卖信息的映射
    uint256 public auctionId = 0; // 拍卖ID
    address public owner; // 拍卖合约创建者

    mapping(address => AggregatorV3Interface) public dataFeeds;

    // allow owner to set data feeds for testing / config
    function setDataFeed(
        address tokenAddress,
        address aggregator
    ) external onlyOwner {
        dataFeeds[tokenAddress] = AggregatorV3Interface(aggregator);
    }

    // 拍卖创建事件
    event AuctionCreated(
        address indexed seller,
        uint256 indexed auctionId,
        uint256 duration,
        uint256 startTime,
        uint256 startPrice,
        address startPriceAddress,
        address indexed nftAddress,
        uint256 tokenId,
        address tokenAddress
    );
    // 拍卖竞价事件
    event AuctionBided(
        address indexed bidder,
        uint256 indexed auctionId,
        address indexed nftAddress,
        uint256 tokenId,
        address tokenAddress,
        uint256 amount
    );
    // 拍卖结束事件
    event AuctionEnded(
        address indexed winner,
        uint256 indexed auctionId,
        address indexed nftAddress,
        uint256 tokenId,
        address tokenAddress,
        uint256 amount
    );

    // init方法供proxy调用
    function initialize() public initializer {
        owner = msg.sender;
        // init预言机喂价代币类型  ETH/USD
        dataFeeds[address(0)] = AggregatorV3Interface(
            0x694AA1769357215DE4FAC081bf1f309aDC325306
        );
        // 使用USDC代币作为示例  USDC/USD
        dataFeeds[
            0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
        ] = AggregatorV3Interface(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E);
    }

    // 设置chainlink数据源
    function getChainlinkDataFeedLatestAnswer(
        address tokenAddress
    ) public view returns (int256) {
        AggregatorV3Interface dataFeed = dataFeeds[tokenAddress];
        require(address(dataFeed) != address(0), "not config the tokenAddress");

        // prettier-ignore
        (
      /* uint80 roundId */
      ,
      int256 answer,
      /*uint256 startedAt*/
      ,
      /*uint256 updatedAt*/
      ,
      /*uint80 answeredInRound*/
    ) = dataFeed.latestRoundData();
        return answer;
    }

    // 创建拍卖
    function createAuction(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _duration
    ) external onlyOwner {
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == msg.sender,
            "not the Owner"
        );
        require(_startPrice > 0, "Invalid start price");
        require(_duration > 10, "Invalid duration");

        auctions[auctionId] = Auction({
            seller: msg.sender,
            duration: _duration,
            startTime: block.timestamp,
            startPrice: _startPrice,
            startPriceAddress: address(0),
            ended: false,
            highestBid: 0,
            highestBidder: address(0),
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            tokenAddress: address(0)
        });

        emit AuctionCreated(
            msg.sender,
            auctionId,
            _duration,
            block.timestamp,
            _startPrice,
            address(0),
            _nftAddress,
            _tokenId,
            address(0)
        );

        auctionId++;
    }

    // 修改支持ERC20和ETH出价, 此处使用USDC代币作为示例
    function bid(
        uint256 _auctionId,
        address _tokenAddress,
        uint256 _amount
    ) external payable nonReentrant {
        // 获取拍卖信息
        Auction storage auction = auctions[_auctionId];
        require(auction.ended == false, "Auction has ended");
        require(
            block.timestamp < auction.startTime + auction.duration,
            "Auction has ended"
        );

        require(_amount > 0, "amount must bigger than 0");
        if (_tokenAddress == address(0)) {
            // ETH
            require(msg.value == _amount, "Invalid amount");
        } else {
            // USDC
            require(msg.value == 0, "ERC20 not need send ETH");
            // transfrom USDC
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }
        // 计算当前出价对应的USD
        uint256 payValue = toUSD(_amount, _tokenAddress);
        // 计算当前auction最高 和 起拍价格对应的USD
        uint256 highestBid = toUSD(auction.highestBid, auction.tokenAddress);
        uint256 startPrice = toUSD(
            auction.startPrice,
            auction.startPriceAddress
        );
        // 检查当前出价是否满足起拍价格
        require(
            payValue > highestBid && payValue >= startPrice,
            "Bid must bigger than highest bid"
        );

        // 退还之前的最高价
        if (auction.highestBidder != address(0)) {
            if (auction.tokenAddress == address(0)) {
                (bool success, ) = payable(auction.highestBidder).call{
                    value: auction.highestBid
                }("");
                require(success, "Transfer failed");
            } else {
                IERC20(auction.tokenAddress).safeTransfer(
                    auction.highestBidder,
                    auction.highestBid
                );
            }
        }

        // 更新最高价和最高价者
        auction.highestBid = _amount;
        auction.highestBidder = msg.sender;
        auction.tokenAddress = _tokenAddress;

        emit AuctionBided(
            msg.sender,
            _auctionId,
            auction.nftAddress,
            auction.tokenId,
            _tokenAddress,
            _amount
        );
    }

    function endAuction(uint256 _auctionId) external nonReentrant {
        // 检查拍卖是否结束
        Auction storage auction = auctions[_auctionId];
        require(auction.ended == false, "auction has ended");
        require(
            block.timestamp >= auction.startTime + auction.duration,
            "Auction is still ongoing"
        );

        // 转移nft到最高出价者
        IERC721(auction.nftAddress).safeTransferFrom(
            auction.seller,
            auction.highestBidder,
            auction.tokenId
        );

        // 转移资金到卖家
        if (auction.tokenAddress == address(0)) {
            // ETH
            (bool success, ) = payable(auction.seller).call{
                value: auction.highestBid
            }("");
            require(success, "Transfer failed");
        } else {
            // ERC20
            IERC20(auction.tokenAddress).safeTransfer(
                auction.seller,
                auction.highestBid
            );
        }
        // 标记拍卖结束
        auction.ended = true;

        emit AuctionEnded(
            auction.highestBidder,
            _auctionId,
            auction.nftAddress,
            auction.tokenId,
            auction.tokenAddress,
            auction.highestBid
        );
    }

    // 统一转为18位小数的USD
    function toUSD(
        uint256 _amount,
        address _tokenAddress
    ) internal view returns (uint256) {
        int256 price = getChainlinkDataFeedLatestAnswer(_tokenAddress);
        require(price > 0, "Invalid price");

        if (_tokenAddress == address(0)) {
            return (_amount * uint256(price)) / 1e10;
        } else {
            // USDC
            return (_amount * uint256(price)) / 1e14;
        }
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can ...");
        _;
    }

    // 升级授权
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {}
}
