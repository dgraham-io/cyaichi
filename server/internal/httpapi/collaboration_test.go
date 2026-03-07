package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestCollaborationChannelsMessagesTasksLifecycle(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Collaboration Workspace")
	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()

	createChannelBody := fmt.Sprintf(`{
	  "workspace_id":"%s",
	  "scope":"team",
	  "name":"Flow Chat",
	  "kind":"flow",
	  "topic":"Discuss the current flow",
	  "flow_doc_id":"%s",
	  "flow_ver_id":"%s",
	  "flow_title":"Triage Flow"
	}`, workspace.WorkspaceID, flowDocID, flowVerID)
	createChannelReq := httptest.NewRequest(http.MethodPost, "/v1/channels", strings.NewReader(createChannelBody))
	createChannelReq.Header.Set("Content-Type", "application/json")
	createChannelRR := httptest.NewRecorder()
	h.mux.ServeHTTP(createChannelRR, createChannelReq)
	if createChannelRR.Code != http.StatusCreated {
		t.Fatalf("create channel failed: %d body=%s", createChannelRR.Code, createChannelRR.Body.String())
	}

	var createdChannel struct {
		DocID string `json:"doc_id"`
		VerID string `json:"ver_id"`
	}
	if err := json.Unmarshal(createChannelRR.Body.Bytes(), &createdChannel); err != nil {
		t.Fatalf("decode create channel response: %v", err)
	}

	listChannelsReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+workspace.WorkspaceID+"/channels", nil)
	listChannelsRR := httptest.NewRecorder()
	h.mux.ServeHTTP(listChannelsRR, listChannelsReq)
	if listChannelsRR.Code != http.StatusOK {
		t.Fatalf("list channels failed: %d body=%s", listChannelsRR.Code, listChannelsRR.Body.String())
	}

	var listedChannels struct {
		Items []struct {
			DocID     string `json:"doc_id"`
			Name      string `json:"name"`
			Kind      string `json:"kind"`
			FlowDocID string `json:"flow_doc_id"`
		} `json:"items"`
	}
	if err := json.Unmarshal(listChannelsRR.Body.Bytes(), &listedChannels); err != nil {
		t.Fatalf("decode list channels response: %v", err)
	}
	if len(listedChannels.Items) != 1 {
		t.Fatalf("expected 1 channel, got %d", len(listedChannels.Items))
	}
	if listedChannels.Items[0].DocID != createdChannel.DocID || listedChannels.Items[0].Kind != "flow" {
		t.Fatalf("unexpected channel item: %+v", listedChannels.Items[0])
	}
	if listedChannels.Items[0].FlowDocID != flowDocID {
		t.Fatalf("expected flow doc ref on channel, got %q", listedChannels.Items[0].FlowDocID)
	}

	renameChannelReq := httptest.NewRequest(
		http.MethodPatch,
		"/v1/channels/"+createdChannel.DocID,
		strings.NewReader(`{"name":"Renamed Flow Chat"}`),
	)
	renameChannelReq.Header.Set("Content-Type", "application/json")
	renameChannelRR := httptest.NewRecorder()
	h.mux.ServeHTTP(renameChannelRR, renameChannelReq)
	if renameChannelRR.Code != http.StatusOK {
		t.Fatalf("rename channel failed: %d body=%s", renameChannelRR.Code, renameChannelRR.Body.String())
	}

	listChannelsAfterRenameReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+workspace.WorkspaceID+"/channels", nil)
	listChannelsAfterRenameRR := httptest.NewRecorder()
	h.mux.ServeHTTP(listChannelsAfterRenameRR, listChannelsAfterRenameReq)
	if listChannelsAfterRenameRR.Code != http.StatusOK {
		t.Fatalf("list channels after rename failed: %d body=%s", listChannelsAfterRenameRR.Code, listChannelsAfterRenameRR.Body.String())
	}
	if err := json.Unmarshal(listChannelsAfterRenameRR.Body.Bytes(), &listedChannels); err != nil {
		t.Fatalf("decode list channels after rename response: %v", err)
	}
	if len(listedChannels.Items) != 1 {
		t.Fatalf("expected 1 channel after rename, got %d", len(listedChannels.Items))
	}
	if listedChannels.Items[0].Name != "Renamed Flow Chat" {
		t.Fatalf("expected renamed channel, got %+v", listedChannels.Items[0])
	}

	createMessageBody := fmt.Sprintf(`{
	  "workspace_id":"%s",
	  "scope":"team",
	  "channel_doc_id":"%s",
	  "format":"markdown",
	  "body":"Please review the selected processor.",
	  "author":{"kind":"user","id":"user_1","label":"Dana"},
	  "refs":[
	    {"kind":"flow","doc_id":"%s","ver_id":"%s","label":"Triage Flow"},
	    {"kind":"processor","id":"n_enrich","node_id":"n_enrich","flow_doc_id":"%s","flow_ver_id":"%s","label":"Summarize + Score"}
	  ]
	}`, workspace.WorkspaceID, createdChannel.DocID, flowDocID, flowVerID, flowDocID, flowVerID)
	createMessageReq := httptest.NewRequest(http.MethodPost, "/v1/messages", strings.NewReader(createMessageBody))
	createMessageReq.Header.Set("Content-Type", "application/json")
	createMessageRR := httptest.NewRecorder()
	h.mux.ServeHTTP(createMessageRR, createMessageReq)
	if createMessageRR.Code != http.StatusCreated {
		t.Fatalf("create message failed: %d body=%s", createMessageRR.Code, createMessageRR.Body.String())
	}

	secondMessageBody := fmt.Sprintf(`{
	  "workspace_id":"%s",
	  "scope":"team",
	  "channel_doc_id":"%s",
	  "body":"Agent reply acknowledged.",
	  "author":{"kind":"agent","id":"planner","label":"Planner Agent"}
	}`, workspace.WorkspaceID, createdChannel.DocID)
	secondMessageReq := httptest.NewRequest(http.MethodPost, "/v1/messages", strings.NewReader(secondMessageBody))
	secondMessageReq.Header.Set("Content-Type", "application/json")
	secondMessageRR := httptest.NewRecorder()
	h.mux.ServeHTTP(secondMessageRR, secondMessageReq)
	if secondMessageRR.Code != http.StatusCreated {
		t.Fatalf("create second message failed: %d body=%s", secondMessageRR.Code, secondMessageRR.Body.String())
	}

	listMessagesReq := httptest.NewRequest(http.MethodGet, "/v1/channels/"+createdChannel.DocID+"/messages", nil)
	listMessagesRR := httptest.NewRecorder()
	h.mux.ServeHTTP(listMessagesRR, listMessagesReq)
	if listMessagesRR.Code != http.StatusOK {
		t.Fatalf("list messages failed: %d body=%s", listMessagesRR.Code, listMessagesRR.Body.String())
	}

	var listedMessages struct {
		Items []struct {
			Body        string           `json:"body"`
			AuthorKind  string           `json:"author_kind"`
			AuthorLabel string           `json:"author_label"`
			Refs        []map[string]any `json:"refs"`
		} `json:"items"`
	}
	if err := json.Unmarshal(listMessagesRR.Body.Bytes(), &listedMessages); err != nil {
		t.Fatalf("decode list messages response: %v", err)
	}
	if len(listedMessages.Items) != 2 {
		t.Fatalf("expected 2 messages, got %d", len(listedMessages.Items))
	}
	if listedMessages.Items[0].AuthorKind != "user" || len(listedMessages.Items[0].Refs) != 2 {
		t.Fatalf("unexpected first message payload: %+v", listedMessages.Items[0])
	}
	if listedMessages.Items[1].AuthorLabel != "Planner Agent" {
		t.Fatalf("expected agent label on second message, got %+v", listedMessages.Items[1])
	}

	createTaskBody := fmt.Sprintf(`{
	  "workspace_id":"%s",
	  "scope":"team",
	  "channel_doc_id":"%s",
	  "title":"Review processor prompt",
	  "body":"Turn the processor feedback into a concrete change.",
	  "created_by":{"kind":"user","id":"user_1","label":"Dana"},
	  "assignee":{"kind":"agent","id":"planner","label":"Planner Agent"},
	  "refs":[
	    {"kind":"processor","id":"n_enrich","node_id":"n_enrich","flow_doc_id":"%s","flow_ver_id":"%s","label":"Summarize + Score"}
	  ]
	}`, workspace.WorkspaceID, createdChannel.DocID, flowDocID, flowVerID)
	createTaskReq := httptest.NewRequest(http.MethodPost, "/v1/tasks", strings.NewReader(createTaskBody))
	createTaskReq.Header.Set("Content-Type", "application/json")
	createTaskRR := httptest.NewRecorder()
	h.mux.ServeHTTP(createTaskRR, createTaskReq)
	if createTaskRR.Code != http.StatusCreated {
		t.Fatalf("create task failed: %d body=%s", createTaskRR.Code, createTaskRR.Body.String())
	}

	var createdTask struct {
		DocID string `json:"doc_id"`
		VerID string `json:"ver_id"`
	}
	if err := json.Unmarshal(createTaskRR.Body.Bytes(), &createdTask); err != nil {
		t.Fatalf("decode create task response: %v", err)
	}

	listTasksReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+workspace.WorkspaceID+"/tasks", nil)
	listTasksRR := httptest.NewRecorder()
	h.mux.ServeHTTP(listTasksRR, listTasksReq)
	if listTasksRR.Code != http.StatusOK {
		t.Fatalf("list tasks failed: %d body=%s", listTasksRR.Code, listTasksRR.Body.String())
	}

	var listedTasks struct {
		Items []struct {
			DocID         string `json:"doc_id"`
			Title         string `json:"title"`
			Status        string `json:"status"`
			AssigneeLabel string `json:"assignee_label"`
		} `json:"items"`
	}
	if err := json.Unmarshal(listTasksRR.Body.Bytes(), &listedTasks); err != nil {
		t.Fatalf("decode list tasks response: %v", err)
	}
	if len(listedTasks.Items) != 1 {
		t.Fatalf("expected 1 task, got %d", len(listedTasks.Items))
	}
	if listedTasks.Items[0].Status != "open" || listedTasks.Items[0].AssigneeLabel != "Planner Agent" {
		t.Fatalf("unexpected task item: %+v", listedTasks.Items[0])
	}

	patchTaskReq := httptest.NewRequest(http.MethodPatch, "/v1/tasks/"+createdTask.DocID, strings.NewReader(`{"status":"done"}`))
	patchTaskReq.Header.Set("Content-Type", "application/json")
	patchTaskRR := httptest.NewRecorder()
	h.mux.ServeHTTP(patchTaskRR, patchTaskReq)
	if patchTaskRR.Code != http.StatusOK {
		t.Fatalf("patch task failed: %d body=%s", patchTaskRR.Code, patchTaskRR.Body.String())
	}

	listTasksAfterReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+workspace.WorkspaceID+"/tasks", nil)
	listTasksAfterRR := httptest.NewRecorder()
	h.mux.ServeHTTP(listTasksAfterRR, listTasksAfterReq)
	if listTasksAfterRR.Code != http.StatusOK {
		t.Fatalf("list tasks after patch failed: %d body=%s", listTasksAfterRR.Code, listTasksAfterRR.Body.String())
	}
	if err := json.Unmarshal(listTasksAfterRR.Body.Bytes(), &listedTasks); err != nil {
		t.Fatalf("decode list tasks after patch response: %v", err)
	}
	if listedTasks.Items[0].Status != "done" {
		t.Fatalf("expected updated task status done, got %+v", listedTasks.Items[0])
	}

	deleteChannelReq := httptest.NewRequest(http.MethodDelete, "/v1/channels/"+createdChannel.DocID, nil)
	deleteChannelRR := httptest.NewRecorder()
	h.mux.ServeHTTP(deleteChannelRR, deleteChannelReq)
	if deleteChannelRR.Code != http.StatusOK {
		t.Fatalf("delete channel failed: %d body=%s", deleteChannelRR.Code, deleteChannelRR.Body.String())
	}

	listChannelsAfterDeleteReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+workspace.WorkspaceID+"/channels", nil)
	listChannelsAfterDeleteRR := httptest.NewRecorder()
	h.mux.ServeHTTP(listChannelsAfterDeleteRR, listChannelsAfterDeleteReq)
	if listChannelsAfterDeleteRR.Code != http.StatusOK {
		t.Fatalf("list channels after delete failed: %d body=%s", listChannelsAfterDeleteRR.Code, listChannelsAfterDeleteRR.Body.String())
	}
	if err := json.Unmarshal(listChannelsAfterDeleteRR.Body.Bytes(), &listedChannels); err != nil {
		t.Fatalf("decode list channels after delete response: %v", err)
	}
	if len(listedChannels.Items) != 1 {
		t.Fatalf("expected 1 archived channel entry, got %d", len(listedChannels.Items))
	}
	if listedChannels.Items[0].Name != "Renamed Flow Chat" {
		t.Fatalf("expected archived channel to retain renamed title, got %+v", listedChannels.Items[0])
	}
}
