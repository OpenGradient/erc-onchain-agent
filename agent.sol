// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct ToolMetadata {
    string name; // name of tool for LLM
    string description; // description for LLM to know when it should use this tool
}

// Tool that is backed by an on-chain contract
contract ContractTool {
    ToolMetadata toolMetadata;
    address toolContract; // contract that implements the agent
    bytes4 toolSelector; // specific method on the tool contract to use
    string toolAbi; // LLM will use this to create tool arguments

    constructor(
        string memory _name,
        string memory _description,
        address _toolContract,
        bytes4 _toolSelector,
        string memory _toolAbi
    ) {
        toolMetadata = ToolMetadata(_name, _description);
        toolContract = _toolContract;
        toolSelector = _toolSelector;
        toolAbi = _toolAbi;
    }


    function run(string memory toolArguments) public returns (bytes memory) {
        bytes memory data = abi.encodeWithSelector(toolSelector, toolContract, toolArguments);
     
        (bool success, bytes memory result) = toolContract.call(data);
        require(success, "Tool call failed");
        return result;
    }
}

// AgentExecutor is provided as a precompile in Vanna for efficiency, implemeted using a reasoning framework
// such as chain-of-though or ReAct
interface AgentExecutor {
    function executeAgent(
        string memory modelId,
        string memory agentDescription,
        ContractTool[] memory contractTools,
        string memory prompt) external returns (string memory);
}

// events emitted by AgentExecutor 
event AgentInvocation(
    string input,
    string answer
);
event AgentError(
    string input,
    string error
);

contract AbstractAgent {
    address agentExecutorContract; // points to Vanna precompile
    string modelId; // LLM model ID to be used on Vanna
    string agentDescription; // describes the overall goals and rules this agent should adhere to
    ContractTool[] contractTools; // list of contract-backed tools the agent can use
   
    constructor(
        address _agentExecutorContract,
        string memory _modelId, 
        string memory _agentDescription,
        ContractTool[] memory _contractTools
    ) {
        agentExecutorContract = _agentExecutorContract;
        modelId = _modelId;
        agentDescription = _agentDescription;
        contractTools = _contractTools;
    }
    
    function run(string memory prompt) public returns (string memory) {
        string memory answer = AgentExecutor(agentExecutorContract).executeAgent(
            modelId, agentDescription, contractTools, prompt);
        return answer;
    }
}

// EXAMPLE

interface Pool {
    function deploy(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balance(address asset) external returns (uint256);
}

contract WalletAgent is AbstractAgent {

    constructor() AbstractAgent(
        address(0x19),
        "llama_model_3",
        string(abi.encodePacked(
            "You are an agent deployed on an Ethereum blockchain, responsible for managing a user's deposits into a liquidity pool. ", 
            "The wallet's owner will give you instructons in simple terms, ",
            "and your goal is to execute the instructions from the user, given the list of tools you can use...")),
        new ContractTool[](3)
    ) {
        contractTools[0] = new ContractTool("Deploy", "Deploy funds into the pool", address(0x123), Pool.deploy.selector, "<deploy-function-abi>");
        contractTools[1] = new ContractTool("Withdraw", "Withdraw funds from the pool", address(0x123), Pool.withdraw.selector, "<withdraw-function-abi>");
        contractTools[2] = new ContractTool("ViewBalance", "See user's balance in the pool", address(0x123), Pool.balance.selector, "<balance-function-abi>");
    }
}