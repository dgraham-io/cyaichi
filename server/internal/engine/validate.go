package engine

import (
	"fmt"
	"sort"
)

func ValidateRunnableFlow(flowDoc FlowDocument) ([]FlowNode, error) {
	nodes := flowDoc.Body.Nodes
	edges := flowDoc.Body.Edges
	if len(nodes) == 0 {
		return nil, fmt.Errorf("flow must contain at least one node")
	}
	if len(edges) == 0 {
		return nil, fmt.Errorf("flow must contain at least one edge")
	}

	nodeByID := make(map[string]FlowNode, len(nodes))
	inputPorts := make(map[string]map[string]struct{}, len(nodes))
	outputPorts := make(map[string]map[string]struct{}, len(nodes))
	for _, node := range nodes {
		if _, exists := nodeByID[node.ID]; exists {
			return nil, fmt.Errorf("duplicate node id: %s", node.ID)
		}
		nodeByID[node.ID] = node

		inPorts := map[string]struct{}{}
		for _, p := range node.Inputs {
			if _, exists := inPorts[p.Port]; exists {
				return nil, fmt.Errorf("duplicate input port %q on node %q", p.Port, node.ID)
			}
			inPorts[p.Port] = struct{}{}
		}
		inputPorts[node.ID] = inPorts

		outPorts := map[string]struct{}{}
		for _, p := range node.Outputs {
			if _, exists := outPorts[p.Port]; exists {
				return nil, fmt.Errorf("duplicate output port %q on node %q", p.Port, node.ID)
			}
			outPorts[p.Port] = struct{}{}
		}
		outputPorts[node.ID] = outPorts
	}

	adjacency := make(map[string][]string, len(nodes))
	indegree := make(map[string]int, len(nodes))
	for _, node := range nodes {
		adjacency[node.ID] = []string{}
		indegree[node.ID] = 0
	}

	incomingPerInputPort := map[string]int{}
	outgoingPerOutputPort := map[string]int{}
	for _, edge := range edges {
		fromNode, ok := nodeByID[edge.From.Node]
		if !ok {
			return nil, fmt.Errorf("edge references missing source node: %s", edge.From.Node)
		}
		_ = fromNode

		toNode, ok := nodeByID[edge.To.Node]
		if !ok {
			return nil, fmt.Errorf("edge references missing target node: %s", edge.To.Node)
		}
		_ = toNode

		if _, ok := outputPorts[edge.From.Node][edge.From.Port]; !ok {
			return nil, fmt.Errorf("edge references missing source output port %q on node %q", edge.From.Port, edge.From.Node)
		}
		if _, ok := inputPorts[edge.To.Node][edge.To.Port]; !ok {
			return nil, fmt.Errorf("edge references missing target input port %q on node %q", edge.To.Port, edge.To.Node)
		}

		outputKey := edge.From.Node + ":" + edge.From.Port
		outgoingPerOutputPort[outputKey]++
		if outgoingPerOutputPort[outputKey] > 1 {
			return nil, fmt.Errorf("single-chain violation: output port %q on node %q has multiple outgoing edges", edge.From.Port, edge.From.Node)
		}

		inputKey := edge.To.Node + ":" + edge.To.Port
		incomingPerInputPort[inputKey]++
		if incomingPerInputPort[inputKey] > 1 {
			return nil, fmt.Errorf("single-chain violation: input port %q on node %q has multiple incoming edges", edge.To.Port, edge.To.Node)
		}

		adjacency[edge.From.Node] = append(adjacency[edge.From.Node], edge.To.Node)
		indegree[edge.To.Node]++
	}

	zero := make([]string, 0, len(nodes))
	for nodeID, deg := range indegree {
		if deg == 0 {
			zero = append(zero, nodeID)
		}
	}
	sort.Strings(zero)

	orderedIDs := make([]string, 0, len(nodes))
	for len(zero) > 0 {
		current := zero[0]
		zero = zero[1:]
		orderedIDs = append(orderedIDs, current)

		for _, neighbor := range adjacency[current] {
			indegree[neighbor]--
			if indegree[neighbor] == 0 {
				zero = append(zero, neighbor)
				sort.Strings(zero)
			}
		}
	}

	if len(orderedIDs) != len(nodes) {
		return nil, fmt.Errorf("flow contains a cycle")
	}

	ordered := make([]FlowNode, 0, len(orderedIDs))
	for _, nodeID := range orderedIDs {
		ordered = append(ordered, nodeByID[nodeID])
	}
	return ordered, nil
}
