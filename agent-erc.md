# ERC Proposal: Interoperable On-chain Agents Standard

Depends on https://eips.ethereum.org/EIPS/eip-165

## Simple Summary

A standard interface and execution framework for interoperable on-chain agents (backed by large language models) and tools that can be nested and combined in unlimited ways to create powerful autonomous entities on Ethereum. 

## Abstract

This ERC proposes the introduction of on-chain interoperable agents, a novel development in the field of decentralized artificial intelligence. Leveraging the capabilities of Large Language Models (LLMs), on-chain agents merge advanced language understanding and intelligence with blockchain technology, offering verifiability, transparency, and accessibility to a myriad of AI applications. These agents, encapsulated within smart contracts on the Ethereum blockchain, can autonomously execute complex tasks, from managing decentralized autonomous organization (DAO) operations to making high-stakes financial decisions. When we let agents interact with each other in a standardized way, we can create a network of autonomous actors that can utilize each other based on needs and specializations, creating a thriving ecosystem. 

In addition, we also introduce the concept of on-chain tools. Tools allow agents to execute specific tasks in their environment - agents can reason about what tools they need to use and in what way, in order to achieve their overall goal. These tools are designed such that they are easy to reuse between different agents, they can either be backed by other agents deployed, or regular smart contracts. 

Furthermore, this ERC introduces pragmatic solutions, such as Retrieval-Augmented Generation (RAG), for the execution of on-chain agents. This also involves exploring both off-chain computational environments, and developing on-chain execution environments tailored to the unique requirements of LLMs, with the goal of optimizing these environments to facilitate the seamless execution of on-chain agents.

## Motivation

### Why we need on-chain agents

On-chain agents leverage Large Language Models (LLMs) within the Ethereum ecosystem to create a powerful fusion of language understanding and reasoning, and decentralized execution. The primary motivation behind this proposal is to address the critical need for trust and transparency in high-impact scenarios where agents might be utilized, such as executing trades and managing DAO proposals. High-value agents make extremely impactful decisions, whether it’s executing on a large trade or deciding on a DAO proposal. Blockchain’s intristic properties give agents the properties we need to be able to trust them with these critical decisions. Specifically, blockchain gives agents traceability, verifiability, immutability, censorship-resistance, global accessibility, and collaborative development. Up until now, almost all LLMs and agents were hosted on centralized infrastructure - we hope that with the introduction of this standard, as well as ongoing technological developments, we can build a pathway for bringing them to the blockchain.

At a high-level, just like off-chain agents, we expect on-chain agents to be able to make decisions on their own, and perform tasks in their environment without any human involvement - though this may be optional. Agents should also be able to adapt to new situations and scenarios that they haven’t been explicitly programmed for, enhancing their flexibility and effectiveness. Finally, we also expect agents to break down goals into small tasks and to utilize tools to achieve them.

### Composability

We aim to create a framework where agents can be built in a standardized and interoperable way, so they can leverage each other to achieve complex tasks and outcomes. We expect agents to build on top of each other, through the use of tools and reasoning frameworks, such as Re-Act or chain-of-thought, where agents decide what tools it should use to achieve its overall goal. Tools can be used by agents to interact with their surrounding environment, such as transferring tokens or making transactions. Tools can either be implemented by other agents, or by regular smart contracts, through implementing the proposed standardized interface, and making it accessible to everyone. We believe agents are only as good as the tools they have, so it’s important to build a collaborative environment where where they can be reused.

To demonstrate how this fits together, we can see an example workflow below where a user is trying to apply for a loan. The lending pool requires that the user’s request is first evaluated by the “Loan application agent”. The agent has access to several tools, including a specialized credit score agent, as well as access to the lending pool DAO that sets what criteria should be used to evaluate new applicants. The criteria can be expressed in easy to understand natural language, and can be changed by a DAO proposal any time. The loan application agent uses a reasoning engine to figure out that it first needs to get the latest evaluation criteria from the DAO, and then use the credit score agent to calculate a credit score based on the given evaluation points. Once it receives the score, it either approves or denies based on a hardcoded limit, which could also be customizable. 

![Loan application workflow](assets/loan-app.png)

This example highlights how powerful nested and composable agents are, where each one can be focused on driving a particular well-defined task, and can offload complexities to other, specialized agents in a completely flexible way. 

### Execution Environment

Despite current challenges in on-chain execution, such as costs and latency, the proposal anticipates technological advancements that will diminish drawbacks over time, envisioning a future where blockchain becomes an increasingly viable ecosystem for both high-impact and everyday AI agents. We also propose 2 different execution modes that should accommodate all future developments. One is an off-chain environment, where only the prompts, tools and overall structure is stored on-chain but the actual execution is handled by off-chain networks, such as oracles. This environment makes it more straightforward to implement agents right now, however has some drawbacks, such as lack of verifiability, and increased latency in execution. The second environment is on-chain, where the end to end execution of the agent is handled by the blockchain network, in a verifiable way. This method’s primary downside is cost, and lack of capabilities to execute AI models on-chain, however, the latest developments in zero-knowledge machine learning and other cryptographic schemes, we believe that on-chain execution will become an increasingly feasible and desirable option. 

## Specification

We are going to define the specifications going from the bottom up, first showing the tool spec, then agent spec and its client interface. Because we want agents to be reused as tools by higher-level agents, agents themselves will also implement the tool spec. 

### Tool definition

A IERCAgentTool defines a tool the agent can use to either retrieve information or take an action in its environment. In most cases, the tool can either be implemented by a traditional smart contract, or by another on-chain agent. Since all agents are wrapped in a smart contract (see below), it is very straightforward to also reuse them as tools in other agents, as it is one of the explicit goals of this ERC. 

```solidity
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IERCAgentTool is IERC165 {

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
    
    struct ParamDescription {
        ParamType type;
        string name;
        string description;
    }
    
    struct InputDescription {        
        []ParamDescription paramDescriptions;
    }
    
    struct ParamValue {
        ParamType type;
        bytes value;
    }
    
    struct Input {
        []ParamValue params;
    }
    
    /// @notice Returns the name of this tool, should be short and meaningful. 
    /// @return The name of the tool.
    function name() external view returns (string memory);
    
    /// @notice Returns the description of this tool, when it should be used
    ///   and what it does at a high level.
    /// @return The description of the tool.
    function description() external view returns (string memory);
    
    /// @notice Returns the type and rough format of the input the tool expects.
    ///   Should be a succint description of what clients need to provide when
    ///   calling this tool.
    /// @returns The description of the input this tool.
    function inputDescription() external view returns (ToolInputDescription memory);
    
    /// @notice Runs the tool with the given input and returns its final answer
    ///   to the given task.
    ///
    /// @param input The input to this tool that is generated using the inputDescription.
    /// @param resultHandler The contract that will receive the result of this tool execution,
    ///   must support the IERCAgentToolClient interface.
    ///
    /// @returns runId when the tool's execution is synchronous, the runId will be -1.
    ///   When it is asynchronous, a non-negative runId will be returned that will be passed to
    ///   the result handler once the operation is ready.
    /// @returns result, only present when the tool was executed synchronously and runId is -1.
    ///   Do not use unless the runId returned was -1. 
    function run(ToolInput memory input, address resultHandler) external virtual returns (uint256 runId, string result);
    
    /// @notice check supported interfaces, adhereing to ERC165.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
```

* name: Gives a meaningful and reasonably unique name to the tool. LLM-backed agents might use this to decide when it’s appropriate to use this tool. Example could be TokenTransferTool, ViewBalanceTool
* description: Gives a short description of what the tool does, and when it should be used. LLM-backed agents could use this description to decide if it’s appropriate to utilize this tool. An example might be: Transfers tokens from one user to another. 
* inputDescription: Describes the format of the input (if any) the tool expects to receive. LLM-backed agents might use this to generate an input for the specific task they want to achieve. Example might be: The input should mention the origin and target address, the token address, and amount. 
* run: Triggers the execution of an tool with a given input. Tools can either be executed synchronously or asynchronously. When executed synchronously, the result will be immediately returned to the called. However, when it is executed asynchronously, result will be passed to the resultHandler, which must implement the IERCAgentClient interface. When executed asynchronously, the run method will commit and return a runId that will be used to invoke the resultHandler once the agent execution has completed. This allows tools and agents to be executed off-chain, and to post the result through this callback mechanism once it’s ready. In addition, the run method may also be used to add custom checks or verification logic to the tool.

### Agent abstract class

Next, we define an agent abstract class. An agent is backed by an LLM, and uses a set of tools to operate in its environment. Since agents themselves can also be used as tools in other agents, we make them implement the IERCAgentTool interface.

```solidity
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

abstract contract IERCAgent is IERCAgentTool {

    /// Logged when the agent completes an execution triggered by calling run.
    /// @params runId the ID of the run
    /// @params executionSteps contains any additional set of details about
    ///   what actions the agent took and how it completed the task, in order. 
    ///   May be empty. 
    /// @params requester the address that requested this execution
    /// @params resultHandler the receiver of the result of this run
    /// @params answer the answer returned by the agent
    event AgentRunResult(
        uint256 indexed runId,
        address requester, 
        string[] executionSteps,
        string answer);

    address agentExecutorContract;
    string modelId;
    string name;
    string description;
    IERCAgentTool.InputDescription inputDescription, 
    IERCAgentTool[] tools;
    uint16 agentMaxIterations; 
    uint256 currentRunId;
    
    /// @notice Creates a new agent
    /// @param agentExecutorContract points to a contract that implements IERCAgentExecutor
    /// @param modelId an identifier for the model that should be used for agent execution
    ///   can be an ID, name, or hash, depending on what the IERCAgentExecutor implementation details
    /// @param name the name of the agent
    /// @param description the description of the agent
    /// @param tools the tools the agent should have access to
    /// @param agentMaxIterations the maximum number of iterations an agent should take
    ///   when running a particular task. One iteration includes one use of a tool. Use
    ///   this to put an upper limit on the runtime of the agent in case it gets stuck.
    constructor(
        address _agentExecutorContract,
        string memory _modelId,
        string memory _name,
        string memory _description,
        string memory _inputDescription,
        IERCAgentTool[] memory _tools,
        uint16 _agentMaxIterations,
    ) {
        agentExecutorContract = _agentExecutorContract;
        model = _model;
        name = _name;
        description = _description;
        
        IERCAgentTool.ParamDescription promptParam = 
            IERCAgentTool.ParamDescription(IERCAgentTool.ParamType.STRING, "prompt", _inputDescription);
        IERCAgentTool.ParamDescription[] params = new IERCAgentTool.ParamDescription[1];
        params[0] = promptParam;
        inputDescription = IERCAgentTool.InputDescription(params);
        
        tools = _tools;
        agentMaxIterations = _agentMaxIterations;
        currentRunId = 0;
    }
    
    /// @notice Returns the name of this agent, should be short and meaningful. 
    /// @return The name of the agent.
    function name() external view returns (string memory) {
        return name;
    }
    
    /// @notice Returns the description of this agent, when it should be used
    ///   and what it does at a high level.
    /// @return The description of the agent.
    function description() external view returns (string memory) {
        return description;
    }
    
    /// @notice Returns the type and rough format of the input the agent expects.
    ///   Should be a succint description of what clients need to provide when
    ///   calling this agent.
    /// @returns The description of the input this agent.
    function inputDescription() external view returns (IERCAgentTool.ParamDescription memory) {
        return inputDescription;
    }
    
    /// @notice Runs the agent with the given input and returns its final answer
    ///   to the given task.
    /// @param input The input to this agent that is generated using the inputDescription.
    /// @param resultHandler The contract that will receive the result of this agent execution,
    ///   must support the IERCAgentClient interface.
    /// @returns The runId for this request that will be used when providing the result
    ///   through the client interface.
    function run(IERCAgentTool.Input memory input, address resultHandler) external virtual returns (uint256 runId, string result) {
        IERCAgentExecutor agentExecutor = IERCAgentExecutor(agentExecutorContract);
        string[] memory agentReasoning = new string[_agentMaxIterations];
        string memory prompt = abi.decode(input.params[0].value, string);
        currentRunId++;
        
        uint16 currentIteration = 0;
        for (; i < agentMaxIterations; i++) {
            AgentIterationResult iterationResult = agentExecutor.runNextIteration(
                modelId,
                name,
                description,
                tools,
                agentReasoning,
                input
            );
            
            if (iterationResult.isFinalAnswer) {
                // agent is done, emit event and return answer
                string[] memory executionSteps = new string[currentIteration];
                for (uint i = 0; i < currentIteration; i++) {
                    executionSteps[i] = agentReasoning[i];
                }
                
                emit AgentRunResult(
                    currentRunId,
                    msg.from,
                    executionSteps,
                    iterationResult.finalAnswer
                );
                
                return (-1, iterationResult.finalAnswer);
            } else {
                IERCAgentTool tool = iterationResult.tool;
                bytes input = iterationResult.toolInput;
                
                (bool success, bytes memory data) = tool.call(input);
                require(success, "Tool execution failed");
                
                // we require tools to return strings 
                string memory result = abi.decode(data, string);
                
                agentReasoning[currentIteration] = string.concat(
                    iterationResult.agentReasoning,
                    "\nObservation: ",
                    data,
                    "\n");
            }
        }
        
        require(false, "Agent failed to produce final answer within agentMaxIterations");
    }
    
    /// @notice check supported interfaces, adhereing to ERC165.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
```

* agentExecutorContract : A contract that can execute a single iteration of an agent. In many cases, this can be a precompile to optimize for speed of execution, cost and flexibility. 
* tools : The set of tools the agent can operate with. Can either be a regular smart contract function, or another agent that’s encapsulated in a smart contract. 
* agentMaxIterations : the maximum number times the agent can use a tool as part of a single execution (ie calling run). This makes sure the agent eventually terminates in case it ever gets lost and doesn’t have a path forward for solving its task.
* AgentRunResult: an event that helps inspect what the agent actually did in more detail, how it arrived at its final answer, and what (if any) actions it took as part of it. For example, if the agent transferred some token on behalf of you to another user, the executionSteps should have an explicit step about this action, such as Transfer{from: A, to: B, token: X, amount: Y}
* run : we implement a synchronous agent execution method that relies on the agentExecutorContract precompile to build and run the LLM prompts using the help of a reasoning engine such as Re-Act. The precompile builds the prompt using the agent name, description, tools and user input, and adds reasoning-specific parts as well to the prompt. It then executes the prompt, parses the response and returns it to the agent contract. The response might either be a finalAnswer , meaning that the agent is done with its task, or a tool invocation, which means that the agents wants to execute a tool in order to achieve its overall goal. In addition to the tool and its input, we also return the agent’s reasoning so far, so for the next iteration it can pick up where it left off and figure out what it needs to do next. We do this until the agent arrives at a final answer, or until we exceed the agentMaxIterations, in which case we throw an error.

### Agent executor contract

```solidity
struct AgentIterationResult {
   bool isFinalAnswer;
   
   string finalAnswer; // only present when isFinalAnswer == true
   
   // below are only present when isFinalAnswer == false
   IERCAgentTool tool;
   bytes toolInput;
   string agentReasoning;
}

// can be implemented as a precompile
interface IERCAgentExecutor {
    function runNextIteration(
        string memory modelId,
        string memory agentName,
        string memory agentDescription,
        IERCAgentTool[] memory tools,
        string[] memory agentReasoning,
        string memory prompt) external returns (AgentIterationResult memory);
}
```

* AgentIterationResult : represents the outcome of one iteration of the agent. Can either be a finalAnswer  which indicates the agent has completed its task, or a tool invocation. finalAnswer is only present when isFinalAnswer is set to true , and the tool invocation fields are only set when isFinalAnswer is false 
* runNextIteration : executes a single iteration in the agent’s reasoning loop. All the parameters including midelId, agentName, agentDescription, inputDescription, tools must be supplied from the agent contract. agentReasoning should be initially empty, however, after each iteration, clients should append the latest agentReasoning string from the AgentIterationResult returned by the last runNextIteration invocation.

### Agent client interface

```solidity
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IERCAgentClient is IERC165 {
   
    /// @notice used to pass the result of the agent invocation back to the caller.
    /// @dev implementations must verify that the sender of this message is the agent
    ///   that they originally issued the request for
    /// @runId the runId that was returned by the run call of agent
    /// @result the final answer and result of the requested task from the agent
    function handleAgentResult(uint256 runId, string memory result) external;
    
    /// @notice check supported interfaces, adhereing to ERC165.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
```

* handleAgentResult: called by the agent when the result of the execution with the given runId is available. Clients could expect this callback to be called either as part of the original run call, when the agent run synchronously, or as a separate transaction if the agent is executed asynchronously. 

## Rationale

The standard is intended to establish an interface and execution framework for agents that can freely interact and build on each other in a standardized way. Similar to how classes expose interfaces for other classes to use in object-oriented programming, agents should be able to communicate and share their capabilities and the type of input they expect from consumers. The primary difference is that for agents, everything is expressed as a natural language string. Agents that want to utilize existing agents deployed to the network can use reasoning frameworks such as chain-of-thought or Re-Act to use “tools” to solve their tasks. These tools could be smart contracts or other agents. When used from a reasoning framework, the name, description and input description serves as direct guidance for the parent agents to decide when it’s appropriate to use it. 

Clients who are using these agents directly, and not through other agents do not have to utilize these additional metadata functions (name, description, input description), but they can still use them as a source of documentation for what the agent is intended for and how it should be used. These clients still benefit from the flexible execution environment laid out in this ERC.

The `IERCAgentClient` interface allows for various agent execution implementations, whether it’s on-chain, off-chain, synchronous or asynchronous, we want to provide as much flexibility for both current and future implementations as possible. Both on-chain and off-chain AI and ML inference solutions are being built in the community, so we want to remain open to a wide range of solutions. In our reference, we provide a synchronous, on-chain agent executor precompile that could be used to run agents seamlessly in a single transaction. However, off-chain or asynchronous executors might be more appropriate for existing technologies that exist. We expect that specialized rollups or networks will make it more feasible to execute agents on-chain. 

## References

### Smart-contract backed tool

We expect agents to utilize 2 types of tools: other agents that live on smart contracts, and standard smart contracts that just run on the EVM. We provide a sample implementation of a smart contract tool below that can easily wrap any function of an existing contract. 

```solidity
// Tool that is backed by a traditional smart contract
abstract contract IERCAgentSmartContractTool is IERCAgentTool {

    string name;
    string description;
    address toolContract; // contract that implements the tool
    bytes4 toolSelector; // specific method on the contract to use
    string toolAbi; // LLM will use this to create method arguments
    
    constructor(
        string memory _name,
        string memory _description,
        address _toolContract,
        bytes4 _toolSelector,
        string memory _toolAbi
    ) {
        name = _name;
        description = _description;
        toolContract = _toolContract;
        toolSelector = _toolSelector;
        toolAbi = _toolAbi;
    }
    
    function name() external view returns (string memory) {
        return name;
    }
    
    function description() external view returns (string memory) {
        return description;
    }
 
    function inputDescription() external view returns (string memory) {
        return "";
    }
       
    function run(string memory toolArguments) public virtual returns (bytes memory) {
        bytes memory data = abi.encodeWithSelector(toolSelector, toolContract, toolArguments);
        
        (bool success, bytes memory result) = toolContract.call(data);
        require(success, "Tool call failed");
        return result;
    }
}
```

### Example agent and executor

Below is the implementation of an actual agent that could be responsible for managing a user’s deposits in a liquidity pool contract, and taking action based on the user’s natural language instructions.

```solidity
interface Pool {
    function deploy(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balance(address asset) external returns (uint256);
}

contract WalletAgent is IERCAgent {

    constructor() IERCAgent(
        address(0x19),
        "llama_model_3",
        string(abi.encodePacked(
            "You are an agent deployed on an Ethereum blockchain, responsible for managing a user's wallet. ", 
            "The wallet's owner will give you instructons in simple terms, ",
            "and your goal is to execute the instructions from the user, given the list of tools you can use...")),
        new ContractTool[](3)
    ) {
        contractTools[0] = new ContractTool("Deploy", "Deploy funds into the pool", address(0x123), Pool.deploy.selector, "<deploy-function-abi>");
        contractTools[1] = new ContractTool("Withdraw", "Withdraw funds from the pool", address(0x123), Pool.withdraw.selector, "<withdraw-function-abi>");
        contractTools[2] = new ContractTool("ViewBalance", "See user's balance in the pool", address(0x123), Pool.balance.selector, "<balance-function-abi>");
    }
}
```

### Agent executor precompile

We provide pseudocode for agent executor precompile that uses the Re-Act framework for reasoning.

```python
def executeAgent(modelId, agentName, agentDescription, tools, agentReasoning, prompt):
    toolsByName = {tool.name: tool for tool in contractTools}
    llm = modelRegistry.get(modelId)
    reasoningEngine = reasoningRegistry.get(Engines.RE_ACT)
    
    llmPrompt = reasoningEngine.buildPrompt(agentDescription, contractTools, agentReasoning, userPrompt)
    llmOutput = llm.run(llmPrompt)
    nextStep = reasoningEngine.parse(llmOutput)
    
    if nextStep.isDone():
        return AgentIterationResult(isFinalAnswer=True, finalAnswer=nextStep.answer)
    
    tool = toolsByName.get(nextStep.toolName)
    toolInputByName = {input.name: input for input in tool.inputDescription.paramDescriptions}
    
    parsedParams = {}
    params = JSON.parse(nextStep.params)
    for param in params.array():
        paramDescription = toolInputByName[param.name]
        parsedParams[param.name] = IERCAgentTool.ParamValue(
            type=paramDescription.type,
            abi.encode(param.value, paramDescription.type))
    
    return AgentIterationResult(
        isFinalAnswer=False,
        tool=tool,
        params=parsedParams,
        agentReasoning=nextStep.reasoning)
```

In this case, the reasoning engine is Re-Act, which is essentially just a very specific prompt format that makes the LLM work better for step by step thinking and reasoning.

Answer the following questions as best you can. 
You have access to the following tools:
- TransferTokenTool: Sends tokens from ...
- ExchangeTokenTool: Swaps tokens from ...

Use the following format:

```
Question: the input question you must answer
Thought: you should always think about what to do
Action: the action to take, should be one of [TransferTokenTool, ExchangeTokenTool]
Action Input: the input to the action
Observation: the result of the action
... (this Thought/Action/Action Input/Observation can repeat N times)
Thought: I now know the final answer
Final Answer: the final answer to the original input question

Begin!

Question: {input}
Thought:{agent_scratchpad}
```

## Security Considerations

### AI

As with any LLM-backed program, users and developers of on-chain agents must exercise caution when letting agents decide and execute actions on their own. Especially in a irreversible environment like Ethereum, where bad decisions cannot be fixed. Finding the right balance between safety and convenience will depend on the use-case. One solution that is often applied for LLMs is requiring human confirmation before any action is taken. This of course restricts the applicability and usability of agents, however might be appropriate for certain high-impact and complex scenarios. 

### Dependencies

Reusing existing smart contracts is a high risk on its own, however when the smart contract is an agent that might make arbitrary choices on its own, the number of edge-cases and potential attack vectors that must be considered could grow substantially. Users of agents must exercise extreme caution when evaluating them, and might want to consider adding additional saferails to make sure the agent doesn’t do something unexpected.

### Prompt injection

Similarly, attackers might try to manipulate the parent agent through prompt injection - returning strings from their agent that tries to derail the original prompt’s intent. Developers must check if the agent can change its metadata, and under what circumstances. Developers might also want to only use agents whose metadata is hardcoded and cannot be updated. 

In case the input prompt comes from users, it is also important to consider all cases where someone might want to do prompt injection attacks against the agent.  Implementing robust input validation and sanitization mechanisms to ensure that the inputs provided to agents are within expected and safe ranges could be cruicial. This helps prevent unexpected behavior due to malicious or erroneous inputs.

### Upgradeability and Versioning

As mentioned in the previous point, upgradeability of agents could pose significant risk factors. However, where it is appropriate, consider including a mechanism for contract upgradeability or versioning to address potential bugs or vulnerabilities. Make sure to provide users with a clear process for migrating to newer versions of agents without disrupting their functionality.

### Gas Limit and Cost Estimation

Given that on-chain execution can consume gas, it's crucial to consider the gas cost associated with running on-chain agents. Provide users with an estimate of the gas required for typical operations and suggest precautions to prevent out-of-gas errors. 

MENTION CALLBACK GAS ESTIMATION

## Copyright Waiver

Copyright and related rights waived via CC0.
