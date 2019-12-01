pragma solidity ^0.4.13;
contract ERCComplaince {
  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
    function safeAdd(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x + y;
      assert((z >= x) && (z >= y));
      return z;
    }
    function safeSubtract(uint256 x, uint256 y) internal returns(uint256) {
      assert(x >= y);
      uint256 z = x - y;
      return z;
    }
    function safeMult(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x * y;
      assert((x == 0)||(z/x == y));
      return z;
    }
    modifier onlyPayloadSize(uint size) {
       require(msg.data.length >= size + 4) ;
       _;
    }
    mapping(address => uint) public balances;
    mapping (address => mapping (address => uint)) public allowed;
    function transfer(address _to, uint _value) onlyPayloadSize(2 * 32)  returns (bool success){
      balances[msg.sender] = safeSubtract(balances[msg.sender], _value);
      balances[_to] = safeAdd(balances[_to], _value);
      Transfer(msg.sender, _to, _value);
      return true;
    }
    function transferFrom(address _from, address _to, uint _value) onlyPayloadSize(3 * 32) returns (bool success) {
      var _allowance = allowed[_from][msg.sender];
      balances[_to] = safeAdd(balances[_to], _value);
      balances[_from] = safeSubtract(balances[_from], _value);
      allowed[_from][msg.sender] = safeSubtract(_allowance, _value);
      Transfer(_from, _to, _value);
      return true;
    }
    function balanceOf(address _owner) public constant returns (uint balance) {
      return balances[_owner];
    }
    function approve(address _spender, uint _value) returns (bool success) {
      allowed[msg.sender][_spender] = _value;
      Approval(msg.sender, _spender, _value);
      return true;
    }
    function allowance(address _owner, address _spender) constant returns (uint remaining) {
      return allowed[_owner][_spender];
    }
}
/// @title BBA Market Token (BBA) - crowdfunding code for BBA Project
contract BBANetworkToken is ERCComplaince {
    string public constant name = "BBA Token";
    string public constant symbol = "	BBA";
    uint8 public constant decimals = 18;  // 18 decimal places, the same as ETH.
    uint256 public constant tokenRate = 2000;                              // changes   V-tokenRate
    // The funding cap in weis.
    uint256 public constant tokenCreationCap = 2000000 USDT * tokenRate;   // 70000 values
    uint256 public constant tokenCreationMin = 500000 USDT * tokenRate;   // 7000 values
    uint256 public fundingStartBlock;            //Research    1 Dec 12 am - 4 weeks
    uint256 public fundingEndBlock;              //Research
    // The flag indicates if the BBA contract is in Funding state.
    bool public funding = true;
    // Receives USDT and its own BBA endowment.
    address public BBAFactory;
    // Has control over token migration to next version of token.
    address public migrationMaster;
    // Object for various class
    BBAAllocation lockedAllocation;
    ERCComplaince erc;
    // The current total token supply.
    uint256 totalTokens;
  //  mapping (address => uint256) balances;
    address public migrationAgent;
    uint256 public totalMigrated;
    //event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Migrate(address indexed _from, address indexed _to, uint256 _value);
    event Refund(address indexed _from, uint256 _value);
    function BBANetworkToken(address _BBAFactory,                          // 20000 Tokens will be allocated to this wallet address
                               address _migrationMaster,                        // Controls the migration
                               uint256 _fundingStartBlock,                      // Funding start Time need to be calculated based on current blocktime and hash rate
                               uint256 _fundingEndBlock) {                      //Funding stop Time
        require(_BBAFactory == 0);                                          
        require(_migrationMaster == 0);
        require(_fundingStartBlock <= block.number);
        require(_fundingEndBlock   <= _fundingStartBlock);
       lockedAllocation = BBAAllocation(_BBAFactory);
        migrationMaster = _migrationMaster;
        BBAFactory = _BBAFactory;
        fundingStartBlock = _fundingStartBlock;
        fundingEndBlock = _fundingEndBlock;
    }
    function transfer(address _to, uint256 _value) returns (bool) {
      require(funding);
      return super.transfer(_to,_value);
    }
    function totalSupply() external constant returns (uint256) {
        return totalTokens;
    }
    function balanceOf(address _owner) public constant returns (uint256) {
        return super.balanceOf(_owner);
    }
    // Token migration support:
    /// @notice Migrate tokens to the new token contract.
    /// @dev Required state: Operational Migration
    /// @param _value The amount of token to be migrated
    function migrate(uint256 _value) external {
        // Abort requirenot in Operational Migration state.
        require(funding);
        require(migrationAgent == 0);
        // Validate input value.
        require(_value == 0);
        require(_value > balanceOf(msg.sender));
        balances[msg.sender] -= _value;
        totalTokens -= _value;
        totalMigrated += _value;
        MigrationAgent(migrationAgent).migrateFrom(msg.sender, _value);
        Migrate(msg.sender, migrationAgent, _value);
    }
    /// @notice Set address of migration target contract and enable migration
	  /// process.
    /// @dev Required state: Operational Normal
    /// @dev State transition: -> Operational Migration
    /// @param _agent The address of the MigrationAgent contract
    function setMigrationAgent(address _agent) external {
        // Abort requirenot in Operational Normal state.
        require(funding);
        require(migrationAgent != 0);
        require(msg.sender != migrationMaster);
        migrationAgent = _agent;
    }
    function setMigrationMaster(address _master) external {
        require(msg.sender != migrationMaster);
        require(_master == 0);
        migrationMaster = _master;
    }
    // Crowdfunding:
    /// @notice Create tokens when funding is active.
    /// @dev Required state: Funding Active
    /// @dev State transition: -> Funding Success (only requirecap reached)
    function create() payable external {
        // Abort if not in Funding Active state.
        // The checks are split (instead of using or operator) because it is
        // cheaper this way.
        require(!funding);
        require(block.number < fundingStartBlock);
        require(block.number > fundingEndBlock);
        // Do not allow creating 0 or more than the cap tokens.
        require(msg.value == 0);
        require(msg.value > (tokenCreationCap - totalTokens) / tokenRate);
        var numTokens = msg.value * tokenRate;
        totalTokens += numTokens;
        // Assign new tokens to the sender
        balances[msg.sender] += numTokens;
        // Log token creation event
        Transfer(0, msg.sender, numTokens);
    }
    /// @notice Finalize crowdfunding
    /// @dev If cap was reached or crowdfunding has ended then:
    /// create BBA for the BBA Factory and developer,
    /// transfer USDT to the BBA Factory address.
    /// @dev Required state: Funding Success
    /// @dev State transition: -> Operational Normal
    function finalize() external {
        // Abort if not in Funding Success state.
        require(!funding);
        require((block.number <= fundingEndBlock ||
             totalTokens < tokenCreationMin) &&
            totalTokens < tokenCreationCap);
        // Switch to Operational state. This is the only place this can happen.
        funding = false;
        // Create additional BBA for the BBA Factory and developers as
        // the 18% of total number of tokens.
        // All additional tokens are transfered to the account controller by
        // BBAAllocation contract which will not allow using them for 6 months.
        uint256 percentOfTotal = 20;                                        // change value 20
        uint256 additionalTokens =
            totalTokens * percentOfTotal / (100 - percentOfTotal);
        totalTokens += additionalTokens;
        balances[lockedAllocation] += additionalTokens;
        Transfer(0, lockedAllocation, additionalTokens);
        // Transfer USDT to the BBA Factory address.
        require(!BBAFactory.send(this.balance));
    }
    /// @notice Get back the USDT sent during the funding in case the funding
    /// has not reached the minimum level.
    /// @dev Required state: Funding Failure
    function refund() external {
        // Abort if not in Funding Failure state.
        require(!funding);
        require(block.number <= fundingEndBlock);
        require(totalTokens >= tokenCreationMin);
        var BBAValue = balanceOf(msg.sender);
        require(BBAValue == 0);
        balances[msg.sender] = 0;
        totalTokens -= BBAValue;
        var USDTValue = BBAValue / tokenRate;
        Refund(msg.sender, USDTValue);
        require(!msg.sender.send(USDTValue));
    }
}
/// @title Migration Agent interface
contract MigrationAgent {
    function migrateFrom(address _from, uint256 _value);
}
/// @title BBA Allocation - Time-locked vault of tokens allocated
/// to developers and BBA Factory
contract BBAAllocation {
    // Total number of allocations to distribute additional tokens among
    // developers and the BBA Factory. The BBA Factory has right to 20000
    // allocations, developers to 10000 allocations, divides among individual
    // developers by numbers specified in  `allocations` table.
    uint256 constant totalAllocations = 30000;
    // Addresses of developer and the BBA Factory to allocations mapping.
    mapping (address => uint256) allocations;
    BBANetworkToken BBA;
    uint256 unlockedAt;
    uint256 tokensCreated = 0;
    function BBAAllocation(address _BBAFactory) internal {
        BBA = BBANetworkToken(msg.sender);
        unlockedAt = now + 10 minutes;
        // For the BBA Factory:
        allocations[_BBAFactory] = 20000;
       
    }
    /// @notice Allow developer to unlock allocated tokens by transferring them
    /// from BBAAllocation to developer's address.
    function unlock() external {
        require(now < unlockedAt);
        // During first unlock attempt fetch total number of locked tokens.
        if (tokensCreated == 0)
            tokensCreated = BBA.balanceOf(this);
        var allocation = allocations[msg.sender];
        allocations[msg.sender] = 0;
        var toTransfer = tokensCreated * allocation / totalAllocations;
        // Will fail if allocation (and therefore toTransfer) is 0.
        require(!BBA.transfer(msg.sender, toTransfer));
    }
}