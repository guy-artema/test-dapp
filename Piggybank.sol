//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

/// @title Motorsport smart contract
/// @author Artema Labs
import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";

contract PiggyBank is ERC721A, IERC2981, Ownable, Pausable {
    string public _uri;
    uint256 public _royaltyPoints = 500;
    mapping(uint256 => uint256) public tokensLockTime;
    uint256 public _maxSupply;
    uint256 public _nextTransferLockDuration = 172800;
    address public _royaltyReceiver;

    address public _clawbackAddress;
    address internal _tokenOwner;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        address royaltyReceiver_
    ) ERC721A(name_, symbol_) {
        setBaseURI(baseURI_);
        _maxSupply = maxSupply_;
        _royaltyReceiver = royaltyReceiver_;
    }

    /**
     * @dev Returns the starting token ID.
     * To change the starting token ID, please override this function.
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /// @notice set the royalty points by contract owner as a percentage * 100
    function setRoyalty(uint256 royalty_, address royaltyReceiver_)
        external
        onlyOwner
    {
        _royaltyPoints = royalty_;
        _royaltyReceiver = royaltyReceiver_;
    }

    /// @notice set the base URI
    function setBaseURI(string memory uri_) public onlyOwner {
        _uri = uri_;
    }

    /// @notice retrieve the contract description for OpenSea
    function contractURI() external view returns (string memory) {
        return string(abi.encodePacked(_uri, "contract.json"));
    }

    /// @notice EIP2981 royalty information implementation function
    function royaltyInfo(uint256, uint256 _salePrice)
        public
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (_royaltyReceiver, (_salePrice * _royaltyPoints) / 10000);
    }

    /// @notice allows owner to burn any token
    function ownerBurn(uint256 tokenId_) external onlyOwner {
        _burn(tokenId_);
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
            interfaceId == 0x80ac58cd || // ERC165 interface ID for ERC721.
            interfaceId == 0x5b5e139f; // ERC165 interface ID for ERC721Metadata.
    }

    /**  @dev tokens can only be transfered by contract deployer if locked*/
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 tokenId,
        uint256 quantity
    ) internal virtual override whenNotPaused {
        if (msg.sender != owner() && msg.sender != _clawbackAddress) {
            require(
                block.timestamp >= tokensLockTime[tokenId],
                "Transfer is not unlocked yet"
            );
            tokensLockTime[tokenId] =
                block.timestamp +
                _nextTransferLockDuration;
        }
        super._beforeTokenTransfers(from, to, tokenId, quantity);
    }

    /* override msg.sender helper function for clawback purposes */
    function _msgSenderERC721A()
        internal
        view
        virtual
        override
        returns (address)
    {
        if (msg.sender == _clawbackAddress) {
            return _tokenOwner;
        } else {
            return msg.sender;
        }
    }

    /* allows owner to set which address can claw back tokens */
    function setClawbackAddress(address address_) external onlyOwner {
        _clawbackAddress = address_;
    }

    /* allows clawback address to move any token */
    function clawback(uint256 tokenId) external whenNotPaused {
        require(
            msg.sender == _clawbackAddress,
            "Can only be called by clawback address"
        );
        _tokenOwner = ownerOf(tokenId);
        safeTransferFrom(_tokenOwner, owner(), tokenId);
    }

    // @dev Returns base URI string
    function _baseURI() internal view override returns (string memory) {
        return _uri;
    }

    /**  @dev tokens can only be preminted if not paused
         @dev admin can also only mint whenNotPaused
    */
    function adminMint(uint256 quantity_) external whenNotPaused onlyOwner {
        require(
            totalSupply() + quantity_ <= _maxSupply,
            "Can't mint more than max supply."
        );
        _mint(msg.sender, quantity_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**  @dev tokens can only be locked if not paused
         @dev onlyOwner can lock tokens
    */
    function lockToken(uint256 tokenId_, uint256 seconds_)
        external
        whenNotPaused
        onlyOwner
    {
        tokensLockTime[tokenId_] = block.timestamp + seconds_;
    }

    function getTokenLockTime(uint256 tokenId_)
        external
        view
        returns (uint256)
    {
        return tokensLockTime[tokenId_];
    }

    function setNextTransfersLockDuration(uint256 nextTransferLockDuration_)
        external
        whenNotPaused
        onlyOwner
    {
        _nextTransferLockDuration = nextTransferLockDuration_;
    }

    /// @dev Allows anyone to trigger withdrawal of contract funds to the owner address
    function withdraw() public whenNotPaused {
        uint256 balance = address(this).balance;
        require((balance > 0), "No funds to withdraw");
        Address.sendValue(payable(owner()), balance);
    }

    receive() external payable {}
}
