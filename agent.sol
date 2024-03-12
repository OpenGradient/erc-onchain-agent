//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

// ========= HIGH LEVEL INTERFACES ========


interface IERCAgentTool {

    /// @notice describes the various types of input parameters a tool can have.
    ///   Right now, only primitive types are supported.
    enum ParamType {
        STRING,
        ADDRESS,
        BOOL,
        INT,
        UINT,
        STRING_ARRAY,
        ADDRESS_ARRAY,
        BOOL_ARAY,
        INT_ARRAY,
        UINT_ARRAY
    }
    
    /// @notice Describes a single parameter for a tool.
    struct ParamDescription {
        ParamType paramType;
        string name;
        string description;
    }
    
    /// @notice Describes all parameters a tool expects.
    struct InputDescription {        
        ParamDescription[] paramDescriptions;
    }
    
    /// @notice Describes a parameter that was generated by the agent for a tool.
    struct ParamValue {
        ParamType paramType;
        bytes value;
    }
    
    /// @notice Describes all parameters that was generated by the agent for a tool.
    struct Input {
        /// @notice the generated parameters for the tool in order, based on the InputDescription.
        ///   You can use this when you want to do custom checks, or overrides before passing them to the tool.
        ParamValue[] params;

        /// @notice the generated parameter values in abi-encoded format, based on the InputDescription.
        ///   You can use this when the InputDescription matches with the function signature 1:1.
        bytes abiEncodedParams;
    }
    
    /// @notice Returns the name of this tool, should be short and meaningful. 
    /// @return Name of the tool.
    function name() external view returns (string memory);
    
    /// @notice Returns the description of this tool, when it should be used
    ///   and what it does at a high level.
    /// @return Description of the tool.
    function description() external view returns (string memory);
    
    /// @notice Returns the type and rough format of the input the tool expects.
    ///   Should be a succint description of what clients need to provide when
    ///   calling this tool.
    /// @return InputDescription of the input to this tool.
    function inputDescription() external view returns (InputDescription memory);
    
    /// @notice Runs the tool with the given input and returns its final answer
    ///   to the given task.
    /// @param input The input to this tool that is generated using the inputDescription.
    /// @param resultHandler The contract that will receive the result of this tool execution,
    ///   must support the IERCAgentToolClient interface.
    /// @return runId when the tool's execution is synchronous, the runId will be -1.
    ///   When it is asynchronous, a non-negative runId will be returned that will be passed to
    ///   the result handler once the operation is ready.
    /// @return result only present when the tool was executed synchronously and runId is -1.
    ///   Do not use unless the runId returned was -1. 
    function run(Input memory input, address resultHandler) external returns (int256 runId, string memory result);
}

interface IERCAgentClient {
   
    /// @notice Used to pass the result of the agent invocation back to the caller.
    /// @dev implementations must verify that the sender of this message is the agent
    ///   that they originally issued the request for
    /// @param runId the runId that was returned by the run call of agent
    /// @param result the final answer and result of the requested task from the agent
    function handleAgentResult(int256 runId, string memory result) external;
    
    /// @notice check supported interfaces, adhereing to ERC165.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


/// ========= SYNCHRONOUS AGENT IMPLEMENTATION ==========


/// @notice Implements a synchronous agent that's backed by an on-chain agentExecutor contract
abstract contract IERCAgent is IERCAgentTool {

    /// @notice Logged when the agent completes an execution triggered by calling run.
    /// @param runId the ID of the run
    /// @param executionSteps contains any additional set of details about
    ///   what actions the agent took and how it completed the task, in order. 
    ///   May be empty. 
    /// @param requester the address that requested this execution
    /// @param answer the answer returned by the agent
    event AgentRunResult(
        int256 indexed runId,
        address requester, 
        string[] executionSteps,
        string answer);

    address agentExecutorContract;
    string modelId;
    string agentName;
    string agentDescription;
    string basePrompt;
    IERCAgentTool.InputDescription agentInputDescription;
    IERCAgentTool[] tools;
    uint16 agentMaxIterations; 
    int256 currentRunId;
    
    /// @notice Creates a new agent
    /// @param _agentExecutorContract points to a contract that implements IERCAgentExecutor
    /// @param _modelId an identifier for the model that should be used for agent execution
    ///   can be an ID, name, or hash, depending on what the IERCAgentExecutor implementation details
    /// @param _name the name of the agent
    /// @param _description the description of the agent
    /// @param _basePrompt the base prompt for the agent that describes its task to the LLM
    /// @param _tools the tools the agent should have access to
    /// @param _agentMaxIterations the maximum number of iterations an agent should take
    ///   when running a particular task. One iteration includes one use of a tool. Use
    ///   this to put an upper limit on the runtime of the agent in case it gets stuck.
    constructor(
        address _agentExecutorContract,
        string memory _modelId,
        string memory _name,
        string memory _description,
        string memory _inputDescription,
        string memory _basePrompt,
        IERCAgentTool[] memory _tools,
        uint16 _agentMaxIterations
    ) {
        agentExecutorContract = _agentExecutorContract;
        modelId = _modelId;
        agentName = _name;
        agentDescription = _description;
        basePrompt = _basePrompt;
        
        IERCAgentTool.ParamDescription memory promptParam = 
            IERCAgentTool.ParamDescription(IERCAgentTool.ParamType.STRING, "prompt", _inputDescription);
        IERCAgentTool.ParamDescription[] memory params = 
            new IERCAgentTool.ParamDescription[](1);
        params[0] = promptParam;
        agentInputDescription = IERCAgentTool.InputDescription(params);
        
        tools = _tools;
        agentMaxIterations = _agentMaxIterations;
        currentRunId = 0;
    }
    
    /// @notice Returns the name of this agent, should be short and meaningful. 
    /// @return The name of the agent.
    function name() external view returns (string memory) {
        return agentName;
    }
    
    /// @notice Returns the description of this agent, when it should be used
    ///   and what it does at a high level.
    /// @return The description of the agent.
    function description() external view returns (string memory) {
        return agentDescription;
    }
    
    /// @notice Returns the type and rough format of the input the agent expects.
    ///   Should be a succint description of what clients need to provide when
    ///   calling this agent.
    /// @return InputDescription of the input this agent.
    function inputDescription() external view returns (IERCAgentTool.InputDescription memory) {
        return agentInputDescription;
    }
    
    /// @notice Runs the agent with the given input and returns its final answer
    ///   to the given task.
    /// @param input The input to this agent that is generated using the inputDescription.
    /// @param resultHandler The contract that will receive the result of this agent execution,
    ///   must support the IERCAgentClient interface. 
    /// @return runId for this request that will be used when providing the result
    ///   through the client interface.
    /// @return result, only present when the tool was executed synchronously and runId is -1.
    ///   Do not use unless the runId returned was -1. 
    function run(IERCAgentTool.Input memory input, address resultHandler) external virtual returns (int256, string memory) {
        require(input.params.length == 1, "Agent always expects a single parameter");

        IERCAgentExecutor agentExecutor = IERCAgentExecutor(agentExecutorContract);
        string[] memory agentReasoning = new string[](agentMaxIterations);
        (string memory prompt) = abi.decode(input.params[0].value, (string));

        currentRunId++;
        
        uint16 currentIteration = 0;
        for (; currentIteration < agentMaxIterations; currentIteration++) {
            AgentIterationResult memory iterationResult = agentExecutor.runNextIteration(
                modelId,
                agentName,
                agentDescription,
                basePrompt,
                tools,
                agentReasoning,
                prompt
            );
            
            if (iterationResult.isFinalAnswer) {
                // agent is done, emit event and return answer
                string[] memory executionSteps = new string[](currentIteration);
                for (uint i = 0; i < currentIteration; i++) {
                    executionSteps[i] = agentReasoning[i];
                }
                
                emit AgentRunResult(
                    currentRunId,
                    msg.sender,
                    executionSteps,
                    iterationResult.finalAnswer
                );
                
                return (-1, iterationResult.finalAnswer);
            } else {
                IERCAgentTool tool = iterationResult.tool;
                (bool success, bytes memory returnValue) = address(tool).call(abi.encodeWithSelector(
                    IERCAgentTool.run.selector, iterationResult.toolInput.abiEncodedParams));
                require(success, "Tool call failed");

                (int256 runId, string memory result) = abi.decode(returnValue, (int256, string));
                require(runId == -1, "Only synchronous tools supported");
                
                agentReasoning[currentIteration] = string.concat(
                    iterationResult.agentReasoning,
                    "\nObservation: ",
                    result,
                    "\n");
            }
        }
        
        revert("Agent failed to produce final answer within agentMaxIterations");
    }
}

struct AgentIterationResult {
   bool isFinalAnswer;
   
   string finalAnswer; // only present when isFinalAnswer == true
   
   // below are only present when isFinalAnswer == false
   IERCAgentTool tool;
   IERCAgentTool.Input toolInput;
   string agentReasoning;
}

// can be implemented as a precompile
interface IERCAgentExecutor {
    function runNextIteration(
        string memory modelId,
        string memory agentName,
        string memory agentDescription,
        string memory basePrompt,
        IERCAgentTool[] memory tools,
        string[] memory agentReasoning,
        string memory prompt) external returns (AgentIterationResult memory);
}


// ======= EXAMPLE AGENT AND TOOLS ==========


/// @notice Simple wrapper tool implementation that can be used to expose simple functions
///   on smart contracts as tools.
contract IERCAgentSmartContractTool is IERCAgentTool {

    string toolName;
    string toolDescription;
    address toolContract; 
    bytes4 toolSelector; 
    IERCAgentTool.InputDescription toolInputDescription;
    
    /// @notice Creates a new tool.
    /// @param _name of the tool
    /// @param _description of the tool
    /// @param _toolContract address of the contract that implements the tool
    /// @param _toolSelector selector of the function on _toolContract that the tool should use
    /// @param _inputDescription must contain all parameters of the function _toolSelector is pointing
    ///   to. Right now, only supports primitive data types.
    constructor(
        string memory _name,
        string memory _description,
        address _toolContract,
        bytes4 _toolSelector,
        IERCAgentTool.InputDescription memory _inputDescription
    ) {
        toolName = _name;
        toolDescription = _description;
        toolContract = _toolContract;
        toolSelector = _toolSelector;
        toolInputDescription = _inputDescription;
    }
    
    function name() external view returns (string memory) {
        return toolName;
    }
    
    function description() external view returns (string memory) {
        return toolDescription;
    }
 
    function inputDescription() external pure returns (IERCAgentTool.InputDescription memory) {
        // TODO fill out
        IERCAgentTool.ParamDescription[] memory paramDescriptions;
        return IERCAgentTool.InputDescription(paramDescriptions);
    }
       
    function run(IERCAgentTool.Input memory input, address resultHandler) external virtual returns (int256, string memory) {
        bytes memory callData = abi.encodeWithSelector(toolSelector, input.abiEncodedParams);
        (bool success, bytes memory returnValue) = toolContract.call(callData);

        require(success, "Tool call failed");

        // TODO convert to observation
        return (-1, "");
    }
}

// demo contract
interface Pool {
    function deploy(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balance(address asset) external returns (uint256);
}

contract WalletAgent is IERCAgent {

    constructor() IERCAgent(
        address(0x19),
        "llama_model_3",
        "Wallet Agent",
        "Use this to deploy or withdraw tokens from a liquidity pool",
        "The action you want to take, the address of the tokens, and the amount",
        string(abi.encodePacked(
            "You are an agent deployed on an Ethereum blockchain, responsible for managing a user's wallet. ", 
            "The wallet's owner will give you instructons in simple terms, ",
            "and your goal is to execute the instructions from the user, given the list of tools you can use...")),
        new IERCAgentTool[](3),
        10
    ) {
        ParamDescription[] memory deployParams = new ParamDescription[](2);
        deployParams[0] = ParamDescription(ParamType.ADDRESS, "asset", "address of the token to deposit");
        deployParams[1] = ParamDescription(ParamType.INT, "amount", "amount of tokens to deposit");
        tools[0] = new IERCAgentSmartContractTool(
            "Deploy", "Deploy funds into the pool", address(0x123), Pool.deploy.selector, IERCAgentTool.InputDescription(deployParams));

        ParamDescription[] memory withdrawParams = new ParamDescription[](2);
        withdrawParams[0] = ParamDescription(ParamType.ADDRESS, "asset", "address of the token to withdraw");
        withdrawParams[1] = ParamDescription(ParamType.INT, "amount", "amount of tokens to withdraw");
        tools[1] = new IERCAgentSmartContractTool(
            "Withdraw", "Withdraw funds from the pool", address(0x123), Pool.withdraw.selector, IERCAgentTool.InputDescription(withdrawParams));

        ParamDescription[] memory viewBalanceParams = new ParamDescription[](1);
        viewBalanceParams[0] = ParamDescription(ParamType.ADDRESS, "asset", "address of the token to view balance for");
        tools[2] = new IERCAgentSmartContractTool(
            "ViewBalance", "See user's balance in the pool", address(0x123), Pool.balance.selector, IERCAgentTool.InputDescription(viewBalanceParams));
    }
}
