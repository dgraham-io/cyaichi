package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
	"github.com/google/uuid"
)

type CollaborationHandler struct {
	store     *store.Store
	validator *schema.Validator
}

type actorRefInput struct {
	Kind  string `json:"kind"`
	ID    string `json:"id"`
	Label string `json:"label"`
}

type collaborationRefInput struct {
	Kind      string `json:"kind"`
	ID        string `json:"id,omitempty"`
	Label     string `json:"label,omitempty"`
	DocID     string `json:"doc_id,omitempty"`
	VerID     string `json:"ver_id,omitempty"`
	Selector  string `json:"selector,omitempty"`
	NodeID    string `json:"node_id,omitempty"`
	FlowDocID string `json:"flow_doc_id,omitempty"`
	FlowVerID string `json:"flow_ver_id,omitempty"`
}

type createChannelRequest struct {
	WorkspaceID string        `json:"workspace_id"`
	Scope       string        `json:"scope"`
	Name        string        `json:"name"`
	Kind        string        `json:"kind"`
	Topic       string        `json:"topic"`
	FlowDocID   string        `json:"flow_doc_id,omitempty"`
	FlowVerID   string        `json:"flow_ver_id,omitempty"`
	FlowTitle   string        `json:"flow_title,omitempty"`
	CreatedBy   actorRefInput `json:"created_by"`
}

type createMessageRequest struct {
	WorkspaceID  string                  `json:"workspace_id"`
	Scope        string                  `json:"scope"`
	ChannelDocID string                  `json:"channel_doc_id"`
	Format       string                  `json:"format"`
	Body         string                  `json:"body"`
	Author       actorRefInput           `json:"author"`
	Refs         []collaborationRefInput `json:"refs"`
}

type createTaskRequest struct {
	WorkspaceID  string                  `json:"workspace_id"`
	Scope        string                  `json:"scope"`
	ChannelDocID string                  `json:"channel_doc_id,omitempty"`
	Title        string                  `json:"title"`
	Body         string                  `json:"body"`
	Status       string                  `json:"status,omitempty"`
	CreatedBy    actorRefInput           `json:"created_by"`
	Assignee     actorRefInput           `json:"assignee"`
	Refs         []collaborationRefInput `json:"refs"`
}

type patchChannelRequest struct {
	Name string `json:"name"`
}

type patchTaskRequest struct {
	Status string `json:"status"`
}

type createMemoryResponse struct {
	DocID string `json:"doc_id"`
	VerID string `json:"ver_id"`
}

type listChannelsResponse struct {
	Items []listChannelItem `json:"items"`
}

type listChannelItem struct {
	DocID      string `json:"doc_id"`
	VerID      string `json:"ver_id"`
	CreatedAt  string `json:"created_at"`
	Name       string `json:"name"`
	Scope      string `json:"scope"`
	Kind       string `json:"kind"`
	Topic      string `json:"topic,omitempty"`
	FlowDocID  string `json:"flow_doc_id,omitempty"`
	FlowVerID  string `json:"flow_ver_id,omitempty"`
	FlowTitle  string `json:"flow_title,omitempty"`
	IsArchived bool   `json:"is_archived"`
}

type listMessagesResponse struct {
	Items []listMessageItem `json:"items"`
}

type listMessageItem struct {
	DocID       string           `json:"doc_id"`
	VerID       string           `json:"ver_id"`
	CreatedAt   string           `json:"created_at"`
	Body        string           `json:"body"`
	Format      string           `json:"format"`
	AuthorKind  string           `json:"author_kind"`
	AuthorID    string           `json:"author_id"`
	AuthorLabel string           `json:"author_label"`
	Refs        []map[string]any `json:"refs"`
}

type listTasksResponse struct {
	Items []listTaskItem `json:"items"`
}

type listTaskItem struct {
	DocID         string           `json:"doc_id"`
	VerID         string           `json:"ver_id"`
	CreatedAt     string           `json:"created_at"`
	Title         string           `json:"title"`
	BodyPreview   string           `json:"body_preview"`
	Scope         string           `json:"scope"`
	Status        string           `json:"status"`
	ChannelDocID  string           `json:"channel_doc_id,omitempty"`
	AssigneeLabel string           `json:"assignee_label,omitempty"`
	Refs          []map[string]any `json:"refs"`
}

func (h *CollaborationHandler) Handle(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/v1/channels":
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		h.handleCreateChannel(w, r)
	case r.URL.Path == "/v1/messages":
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		h.handleCreateMessage(w, r)
	case r.URL.Path == "/v1/tasks":
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		h.handleCreateTask(w, r)
	default:
		if channelDocID, ok := parseChannelMessagesPath(r.URL.Path); ok {
			if r.Method != http.MethodGet {
				w.Header().Set("Allow", "GET")
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
				return
			}
			h.handleListMessagesForChannel(w, r, channelDocID)
			return
		}
		if channelDocID, ok := parseChannelPath(r.URL.Path); ok {
			switch r.Method {
			case http.MethodPatch:
				h.handlePatchChannel(w, r, channelDocID)
			case http.MethodDelete:
				h.handleDeleteChannel(w, r, channelDocID)
			default:
				w.Header().Set("Allow", "DELETE, PATCH")
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}
		if taskDocID, ok := parseTaskPath(r.URL.Path); ok {
			if r.Method != http.MethodPatch {
				w.Header().Set("Allow", "PATCH")
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
				return
			}
			h.handlePatchTask(w, r, taskDocID)
			return
		}
		http.NotFound(w, r)
	}
}

func (h *CollaborationHandler) HandleWorkspaceChannels(w http.ResponseWriter, r *http.Request, workspaceID string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := h.validateWorkspace(r.Context(), workspaceID); err != nil {
		h.respondWorkspaceError(w, r, err)
		return
	}

	rows, err := h.store.ListDocumentsByType(r.Context(), workspaceID, "memory", 200, 0)
	if err != nil {
		http.Error(w, "failed to list channels", http.StatusInternalServerError)
		return
	}

	seen := make(map[string]struct{})
	items := make([]listChannelItem, 0)
	for _, row := range rows {
		if _, ok := seen[row.DocID]; ok {
			continue
		}
		docMap, body, ok := decodeMemoryDoc(row.JSON)
		if !ok || memoryType(body) != "channel" {
			continue
		}
		seen[row.DocID] = struct{}{}
		attrs := attrsMap(body)
		items = append(items, listChannelItem{
			DocID:      row.DocID,
			VerID:      row.VerID,
			CreatedAt:  row.CreatedAt,
			Name:       memoryTitle(docMap),
			Scope:      stringValue(body["scope"]),
			Kind:       stringValue(attrs["channel_kind"]),
			Topic:      stringValue(attrs["topic"]),
			FlowDocID:  stringValue(attrs["flow_doc_id"]),
			FlowVerID:  stringValue(attrs["flow_ver_id"]),
			FlowTitle:  stringValue(attrs["flow_title"]),
			IsArchived: boolValue(attrs["is_archived"]),
		})
	}

	writeJSON(w, http.StatusOK, listChannelsResponse{Items: items})
}

func (h *CollaborationHandler) HandleWorkspaceTasks(w http.ResponseWriter, r *http.Request, workspaceID string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := h.validateWorkspace(r.Context(), workspaceID); err != nil {
		h.respondWorkspaceError(w, r, err)
		return
	}

	rows, err := h.store.ListDocumentsByType(r.Context(), workspaceID, "memory", 200, 0)
	if err != nil {
		http.Error(w, "failed to list tasks", http.StatusInternalServerError)
		return
	}

	seen := make(map[string]struct{})
	items := make([]listTaskItem, 0)
	for _, row := range rows {
		if _, ok := seen[row.DocID]; ok {
			continue
		}
		docMap, body, ok := decodeMemoryDoc(row.JSON)
		if !ok || memoryType(body) != "task" {
			continue
		}
		seen[row.DocID] = struct{}{}
		attrs := attrsMap(body)
		items = append(items, listTaskItem{
			DocID:         row.DocID,
			VerID:         row.VerID,
			CreatedAt:     row.CreatedAt,
			Title:         memoryTitle(docMap),
			BodyPreview:   preview(memoryBodyText(body), 120),
			Scope:         stringValue(body["scope"]),
			Status:        taskStatus(attrs),
			ChannelDocID:  stringValue(attrs["channel_doc_id"]),
			AssigneeLabel: actorLabel(attrs["assignee"]),
			Refs:          refList(attrs["refs"]),
		})
	}

	writeJSON(w, http.StatusOK, listTasksResponse{Items: items})
}

func (h *CollaborationHandler) handleCreateChannel(w http.ResponseWriter, r *http.Request) {
	var req createChannelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if err := h.validateWorkspace(r.Context(), req.WorkspaceID); err != nil {
		h.respondWorkspaceError(w, r, err)
		return
	}
	if strings.TrimSpace(req.Name) == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}
	if !isValidScope(req.Scope) {
		http.Error(w, "scope must be one of personal, team, org, public_read", http.StatusBadRequest)
		return
	}
	if !isValidChannelKind(req.Kind) {
		http.Error(w, "kind must be one of workspace, flow, topic, dm", http.StatusBadRequest)
		return
	}
	if req.Kind == "flow" && strings.TrimSpace(req.FlowDocID) == "" {
		http.Error(w, "flow_doc_id is required for flow channels", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.FlowDocID) != "" {
		if _, err := uuid.Parse(req.FlowDocID); err != nil {
			http.Error(w, "flow_doc_id must be a valid UUID", http.StatusBadRequest)
			return
		}
	}
	if strings.TrimSpace(req.FlowVerID) != "" {
		if _, err := uuid.Parse(req.FlowVerID); err != nil {
			http.Error(w, "flow_ver_id must be a valid UUID", http.StatusBadRequest)
			return
		}
	}

	docID := uuid.NewString()
	verID := uuid.NewString()
	createdAt := time.Now().UTC().Format(time.RFC3339Nano)
	attrs := map[string]any{
		"channel_kind": req.Kind,
		"is_archived":  false,
	}
	if topic := strings.TrimSpace(req.Topic); topic != "" {
		attrs["topic"] = topic
	}
	if req.FlowDocID != "" {
		attrs["flow_doc_id"] = req.FlowDocID
	}
	if req.FlowVerID != "" {
		attrs["flow_ver_id"] = req.FlowVerID
	}
	if title := strings.TrimSpace(req.FlowTitle); title != "" {
		attrs["flow_title"] = title
	}
	links := []map[string]any{}
	if req.FlowDocID != "" && req.FlowVerID != "" {
		links = append(links, map[string]any{
			"doc_id":   req.FlowDocID,
			"ver_id":   req.FlowVerID,
			"selector": "pinned",
		})
	}

	docMap := map[string]any{
		"doc_type":     "memory",
		"doc_id":       docID,
		"ver_id":       verID,
		"workspace_id": req.WorkspaceID,
		"created_at":   createdAt,
		"meta": map[string]any{
			"title": strings.TrimSpace(req.Name),
		},
		"body": map[string]any{
			"scope": req.Scope,
			"type":  "channel",
			"content": map[string]any{
				"format": "text/plain",
				"body":   strings.TrimSpace(req.Topic),
			},
			"links":      links,
			"attrs":      attrs,
			"provenance": map[string]any{"created_by": actorMap(req.CreatedBy, "user", "local-user", "You")},
		},
	}

	if err := h.storeMemoryDoc(r, docMap); err != nil {
		h.respondStoreError(w, err, "channel")
		return
	}

	writeJSON(w, http.StatusCreated, createMemoryResponse{DocID: docID, VerID: verID})
}

func (h *CollaborationHandler) handlePatchChannel(w http.ResponseWriter, r *http.Request, channelDocID string) {
	var req patchChannelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}

	latestDoc, docMap, body, err := h.latestMemoryDocOfType(r.Context(), channelDocID, "channel")
	if err != nil {
		h.respondDocLookupError(w, r, err, "channel")
		return
	}

	meta, _ := docMap["meta"].(map[string]any)
	if meta == nil {
		meta = map[string]any{}
	}
	meta["title"] = name
	docMap["meta"] = meta
	docMap["ver_id"] = uuid.NewString()
	docMap["created_at"] = time.Now().UTC().Format(time.RFC3339Nano)
	docMap["parents"] = []string{latestDoc.VerID}
	docMap["body"] = body

	if err := h.storeMemoryDoc(r, docMap); err != nil {
		h.respondStoreError(w, err, "channel")
		return
	}

	writeJSON(w, http.StatusOK, createMemoryResponse{
		DocID: channelDocID,
		VerID: stringValue(docMap["ver_id"]),
	})
}

func (h *CollaborationHandler) handleDeleteChannel(w http.ResponseWriter, r *http.Request, channelDocID string) {
	latestDoc, docMap, body, err := h.latestMemoryDocOfType(r.Context(), channelDocID, "channel")
	if err != nil {
		h.respondDocLookupError(w, r, err, "channel")
		return
	}

	attrs := attrsMap(body)
	attrs["is_archived"] = true
	body["attrs"] = attrs

	meta, _ := docMap["meta"].(map[string]any)
	if meta == nil {
		meta = map[string]any{}
	}
	meta["comment"] = "cyaichi.deleted=true"
	docMap["meta"] = meta
	docMap["body"] = body
	docMap["ver_id"] = uuid.NewString()
	docMap["created_at"] = time.Now().UTC().Format(time.RFC3339Nano)
	docMap["parents"] = []string{latestDoc.VerID}

	if err := h.storeMemoryDoc(r, docMap); err != nil {
		h.respondStoreError(w, err, "channel")
		return
	}

	writeJSON(w, http.StatusOK, createMemoryResponse{
		DocID: channelDocID,
		VerID: stringValue(docMap["ver_id"]),
	})
}

func (h *CollaborationHandler) handleCreateMessage(w http.ResponseWriter, r *http.Request) {
	var req createMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if err := h.validateWorkspace(r.Context(), req.WorkspaceID); err != nil {
		h.respondWorkspaceError(w, r, err)
		return
	}
	if !isValidScope(req.Scope) {
		http.Error(w, "scope must be one of personal, team, org, public_read", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.ChannelDocID) == "" {
		http.Error(w, "channel_doc_id is required", http.StatusBadRequest)
		return
	}
	if _, err := uuid.Parse(req.ChannelDocID); err != nil {
		http.Error(w, "channel_doc_id must be a valid UUID", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Body) == "" {
		http.Error(w, "body is required", http.StatusBadRequest)
		return
	}
	format := strings.TrimSpace(req.Format)
	if format == "" {
		format = "markdown"
	}

	channelDoc, channelMap, channelBody, err := h.latestMemoryDocOfType(r.Context(), req.ChannelDocID, "channel")
	if err != nil {
		h.respondDocLookupError(w, r, err, "channel")
		return
	}
	if channelDoc.WorkspaceID != req.WorkspaceID {
		http.Error(w, "channel does not belong to workspace", http.StatusBadRequest)
		return
	}

	docID := uuid.NewString()
	verID := uuid.NewString()
	createdAt := time.Now().UTC().Format(time.RFC3339Nano)
	attrs := map[string]any{
		"channel_doc_id": req.ChannelDocID,
		"author":         actorMap(req.Author, "user", "local-user", "You"),
	}
	if refs := compactRefs(req.Refs); len(refs) > 0 {
		attrs["refs"] = refs
	}
	links := []map[string]any{
		{
			"doc_id":   channelDoc.DocID,
			"ver_id":   channelDoc.VerID,
			"selector": "pinned",
		},
	}
	links = append(links, extractDocRefLinks(req.Refs)...)

	docMap := map[string]any{
		"doc_type":     "memory",
		"doc_id":       docID,
		"ver_id":       verID,
		"workspace_id": req.WorkspaceID,
		"created_at":   createdAt,
		"body": map[string]any{
			"scope": req.Scope,
			"type":  "message",
			"content": map[string]any{
				"format": format,
				"body":   strings.TrimSpace(req.Body),
			},
			"links":      links,
			"attrs":      attrs,
			"provenance": map[string]any{"created_by": actorMap(req.Author, "user", "local-user", "You")},
		},
	}
	if channelTitle := memoryTitle(channelMap); channelTitle != "" {
		docMap["meta"] = map[string]any{
			"title": preview(channelTitle+": "+strings.TrimSpace(req.Body), 80),
		}
	}
	if channelScope := stringValue(channelBody["scope"]); req.Scope == "" && channelScope != "" {
		bodyMap, _ := docMap["body"].(map[string]any)
		bodyMap["scope"] = channelScope
		docMap["body"] = bodyMap
	}

	if err := h.storeMemoryDoc(r, docMap); err != nil {
		h.respondStoreError(w, err, "message")
		return
	}

	writeJSON(w, http.StatusCreated, createMemoryResponse{DocID: docID, VerID: verID})
}

func (h *CollaborationHandler) handleCreateTask(w http.ResponseWriter, r *http.Request) {
	var req createTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if err := h.validateWorkspace(r.Context(), req.WorkspaceID); err != nil {
		h.respondWorkspaceError(w, r, err)
		return
	}
	if !isValidScope(req.Scope) {
		http.Error(w, "scope must be one of personal, team, org, public_read", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Title) == "" {
		http.Error(w, "title is required", http.StatusBadRequest)
		return
	}
	status := normalizeTaskStatus(req.Status)
	if status == "" {
		http.Error(w, "status must be one of open, in_progress, done", http.StatusBadRequest)
		return
	}

	links := extractDocRefLinks(req.Refs)
	attrs := map[string]any{
		"status": status,
	}
	if assignee := actorMap(req.Assignee, "", "", ""); len(assignee) > 0 {
		attrs["assignee"] = assignee
	}
	if refs := compactRefs(req.Refs); len(refs) > 0 {
		attrs["refs"] = refs
	}
	if channelID := strings.TrimSpace(req.ChannelDocID); channelID != "" {
		if _, err := uuid.Parse(channelID); err != nil {
			http.Error(w, "channel_doc_id must be a valid UUID", http.StatusBadRequest)
			return
		}
		channelDoc, _, _, err := h.latestMemoryDocOfType(r.Context(), channelID, "channel")
		if err != nil {
			h.respondDocLookupError(w, r, err, "channel")
			return
		}
		if channelDoc.WorkspaceID != req.WorkspaceID {
			http.Error(w, "channel does not belong to workspace", http.StatusBadRequest)
			return
		}
		attrs["channel_doc_id"] = channelID
		links = append(links, map[string]any{
			"doc_id":   channelDoc.DocID,
			"ver_id":   channelDoc.VerID,
			"selector": "pinned",
		})
	}

	docID := uuid.NewString()
	verID := uuid.NewString()
	createdAt := time.Now().UTC().Format(time.RFC3339Nano)
	docMap := map[string]any{
		"doc_type":     "memory",
		"doc_id":       docID,
		"ver_id":       verID,
		"workspace_id": req.WorkspaceID,
		"created_at":   createdAt,
		"meta": map[string]any{
			"title": strings.TrimSpace(req.Title),
		},
		"body": map[string]any{
			"scope": req.Scope,
			"type":  "task",
			"content": map[string]any{
				"format": "markdown",
				"body":   strings.TrimSpace(req.Body),
			},
			"links":      links,
			"attrs":      attrs,
			"provenance": map[string]any{"created_by": actorMap(req.CreatedBy, "user", "local-user", "You")},
		},
	}

	if err := h.storeMemoryDoc(r, docMap); err != nil {
		h.respondStoreError(w, err, "task")
		return
	}

	writeJSON(w, http.StatusCreated, createMemoryResponse{DocID: docID, VerID: verID})
}

func (h *CollaborationHandler) handlePatchTask(w http.ResponseWriter, r *http.Request, taskDocID string) {
	var req patchTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	status := normalizeTaskStatus(req.Status)
	if status == "" {
		http.Error(w, "status must be one of open, in_progress, done", http.StatusBadRequest)
		return
	}

	latestDoc, docMap, body, err := h.latestMemoryDocOfType(r.Context(), taskDocID, "task")
	if err != nil {
		h.respondDocLookupError(w, r, err, "task")
		return
	}

	attrs := attrsMap(body)
	attrs["status"] = status
	body["attrs"] = attrs
	docMap["body"] = body
	docMap["ver_id"] = uuid.NewString()
	docMap["created_at"] = time.Now().UTC().Format(time.RFC3339Nano)
	docMap["parents"] = []string{latestDoc.VerID}

	if err := h.storeMemoryDoc(r, docMap); err != nil {
		h.respondStoreError(w, err, "task")
		return
	}

	writeJSON(w, http.StatusOK, createMemoryResponse{
		DocID: taskDocID,
		VerID: stringValue(docMap["ver_id"]),
	})
}

func (h *CollaborationHandler) handleListMessagesForChannel(w http.ResponseWriter, r *http.Request, channelDocID string) {
	channelDoc, _, _, err := h.latestMemoryDocOfType(r.Context(), channelDocID, "channel")
	if err != nil {
		h.respondDocLookupError(w, r, err, "channel")
		return
	}

	rows, err := h.store.ListDocumentsByType(r.Context(), channelDoc.WorkspaceID, "memory", 500, 0)
	if err != nil {
		http.Error(w, "failed to list messages", http.StatusInternalServerError)
		return
	}

	items := make([]listMessageItem, 0)
	for i := len(rows) - 1; i >= 0; i-- {
		row := rows[i]
		_, body, ok := decodeMemoryDoc(row.JSON)
		if !ok || memoryType(body) != "message" {
			continue
		}
		attrs := attrsMap(body)
		if stringValue(attrs["channel_doc_id"]) != channelDocID {
			continue
		}
		author := objectValue(attrs["author"])
		content := objectValue(body["content"])
		items = append(items, listMessageItem{
			DocID:       row.DocID,
			VerID:       row.VerID,
			CreatedAt:   row.CreatedAt,
			Body:        stringValue(content["body"]),
			Format:      stringValue(content["format"]),
			AuthorKind:  stringValue(author["kind"]),
			AuthorID:    stringValue(author["id"]),
			AuthorLabel: defaultString(stringValue(author["label"]), stringValue(author["id"])),
			Refs:        refList(attrs["refs"]),
		})
	}

	writeJSON(w, http.StatusOK, listMessagesResponse{Items: items})
}

func (h *CollaborationHandler) storeMemoryDoc(r *http.Request, docMap map[string]any) error {
	docBytes, err := json.Marshal(docMap)
	if err != nil {
		return err
	}
	if err := h.validator.Validate(docBytes); err != nil {
		return err
	}
	return h.store.PutDocument(r.Context(), store.Document{
		DocType:     "memory",
		DocID:       stringValue(docMap["doc_id"]),
		VerID:       stringValue(docMap["ver_id"]),
		WorkspaceID: stringValue(docMap["workspace_id"]),
		CreatedAt:   stringValue(docMap["created_at"]),
		JSON:        string(docBytes),
	})
}

func (h *CollaborationHandler) latestMemoryDocOfType(ctx context.Context, docID, expectedType string) (store.Document, map[string]any, map[string]any, error) {
	doc, err := h.store.GetLatestDocumentVersion(ctx, "memory", docID)
	if err != nil {
		return store.Document{}, nil, nil, err
	}
	docMap, body, ok := decodeMemoryDoc(doc.JSON)
	if !ok {
		return store.Document{}, nil, nil, fmt.Errorf("invalid memory document")
	}
	if memoryType(body) != expectedType {
		return store.Document{}, nil, nil, store.ErrDocumentNotFound
	}
	return doc, docMap, body, nil
}

func (h *CollaborationHandler) validateWorkspace(ctx context.Context, workspaceID string) error {
	if _, err := uuid.Parse(workspaceID); err != nil {
		return fmt.Errorf("workspace_id must be a valid UUID")
	}
	workspaceDoc, err := h.store.GetLatestWorkspaceDoc(ctx, workspaceID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		return err
	}
	if err != nil {
		return fmt.Errorf("fetch workspace: %w", err)
	}
	if workspaceDoc.DocID != workspaceID || workspaceDoc.WorkspaceID != workspaceID {
		return store.ErrDocumentNotFound
	}
	return nil
}

func (h *CollaborationHandler) respondWorkspaceError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, store.ErrDocumentNotFound):
		http.NotFound(w, r)
	case strings.Contains(err.Error(), "valid UUID"):
		http.Error(w, err.Error(), http.StatusBadRequest)
	default:
		http.Error(w, "failed to fetch workspace", http.StatusInternalServerError)
	}
}

func (h *CollaborationHandler) respondDocLookupError(w http.ResponseWriter, r *http.Request, err error, label string) {
	switch {
	case errors.Is(err, store.ErrDocumentNotFound):
		http.Error(w, label+" not found", http.StatusNotFound)
	default:
		http.Error(w, "failed to fetch "+label, http.StatusInternalServerError)
	}
}

func (h *CollaborationHandler) respondStoreError(w http.ResponseWriter, err error, label string) {
	switch {
	case errors.Is(err, store.ErrDocumentExists):
		http.Error(w, label+" already exists", http.StatusConflict)
	case err != nil && strings.Contains(err.Error(), "validation failed"):
		http.Error(w, err.Error(), http.StatusBadRequest)
	default:
		http.Error(w, "failed to store "+label, http.StatusInternalServerError)
	}
}

func parseChannelPath(path string) (channelDocID string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 3 || parts[0] != "v1" || parts[1] != "channels" {
		return "", false
	}
	if parts[2] == "" {
		return "", false
	}
	return parts[2], true
}

func decodeMemoryDoc(raw string) (map[string]any, map[string]any, bool) {
	var docMap map[string]any
	if err := json.Unmarshal([]byte(raw), &docMap); err != nil {
		return nil, nil, false
	}
	body, ok := docMap["body"].(map[string]any)
	if !ok {
		return nil, nil, false
	}
	return docMap, body, true
}

func memoryType(body map[string]any) string {
	return stringValue(body["type"])
}

func attrsMap(body map[string]any) map[string]any {
	attrs, _ := body["attrs"].(map[string]any)
	if attrs == nil {
		return map[string]any{}
	}
	return attrs
}

func objectValue(value any) map[string]any {
	object, _ := value.(map[string]any)
	if object == nil {
		return map[string]any{}
	}
	return object
}

func memoryTitle(docMap map[string]any) string {
	meta, _ := docMap["meta"].(map[string]any)
	if meta == nil {
		return ""
	}
	return stringValue(meta["title"])
}

func memoryBodyText(body map[string]any) string {
	content, _ := body["content"].(map[string]any)
	if content == nil {
		return ""
	}
	return stringValue(content["body"])
}

func actorMap(input actorRefInput, fallbackKind, fallbackID, fallbackLabel string) map[string]any {
	kind := strings.TrimSpace(input.Kind)
	id := strings.TrimSpace(input.ID)
	label := strings.TrimSpace(input.Label)
	if kind == "" {
		kind = fallbackKind
	}
	if id == "" {
		id = fallbackID
	}
	if label == "" {
		label = fallbackLabel
	}
	if kind == "" || id == "" {
		return map[string]any{}
	}
	actor := map[string]any{
		"kind": kind,
		"id":   id,
	}
	if label != "" {
		actor["label"] = label
	}
	return actor
}

func actorLabel(value any) string {
	return stringValue(objectValue(value)["label"])
}

func compactRefs(refs []collaborationRefInput) []map[string]any {
	items := make([]map[string]any, 0, len(refs))
	for _, ref := range refs {
		item := map[string]any{}
		if kind := strings.TrimSpace(ref.Kind); kind != "" {
			item["kind"] = kind
		}
		if id := strings.TrimSpace(ref.ID); id != "" {
			item["id"] = id
		}
		if label := strings.TrimSpace(ref.Label); label != "" {
			item["label"] = label
		}
		if docID := strings.TrimSpace(ref.DocID); docID != "" {
			item["doc_id"] = docID
		}
		if verID := strings.TrimSpace(ref.VerID); verID != "" {
			item["ver_id"] = verID
		}
		if selector := strings.TrimSpace(ref.Selector); selector != "" {
			item["selector"] = selector
		}
		if nodeID := strings.TrimSpace(ref.NodeID); nodeID != "" {
			item["node_id"] = nodeID
		}
		if flowDocID := strings.TrimSpace(ref.FlowDocID); flowDocID != "" {
			item["flow_doc_id"] = flowDocID
		}
		if flowVerID := strings.TrimSpace(ref.FlowVerID); flowVerID != "" {
			item["flow_ver_id"] = flowVerID
		}
		if _, ok := item["kind"]; !ok {
			continue
		}
		if _, ok := item["id"]; !ok && item["doc_id"] == nil && item["node_id"] == nil {
			continue
		}
		items = append(items, item)
	}
	return items
}

func extractDocRefLinks(refs []collaborationRefInput) []map[string]any {
	items := make([]map[string]any, 0)
	for _, ref := range refs {
		docID := strings.TrimSpace(ref.DocID)
		verID := strings.TrimSpace(ref.VerID)
		if docID == "" || verID == "" {
			continue
		}
		if _, err := uuid.Parse(docID); err != nil {
			continue
		}
		if _, err := uuid.Parse(verID); err != nil {
			continue
		}
		items = append(items, map[string]any{
			"doc_id":   docID,
			"ver_id":   verID,
			"selector": "pinned",
		})
	}
	return items
}

func refList(value any) []map[string]any {
	raw, ok := value.([]any)
	if !ok {
		return []map[string]any{}
	}
	items := make([]map[string]any, 0, len(raw))
	for _, item := range raw {
		ref, ok := item.(map[string]any)
		if !ok {
			continue
		}
		items = append(items, ref)
	}
	return items
}

func stringValue(value any) string {
	text, _ := value.(string)
	return text
}

func boolValue(value any) bool {
	flag, _ := value.(bool)
	return flag
}

func defaultString(value, fallback string) string {
	if strings.TrimSpace(value) != "" {
		return value
	}
	return fallback
}

func taskStatus(attrs map[string]any) string {
	status := normalizeTaskStatus(stringValue(attrs["status"]))
	if status == "" {
		return "open"
	}
	return status
}

func normalizeTaskStatus(status string) string {
	switch strings.TrimSpace(status) {
	case "", "open":
		return "open"
	case "in_progress":
		return "in_progress"
	case "done":
		return "done"
	default:
		return ""
	}
}

func isValidScope(scope string) bool {
	switch scope {
	case "personal", "team", "org", "public_read":
		return true
	default:
		return false
	}
}

func isValidChannelKind(kind string) bool {
	switch kind {
	case "workspace", "flow", "topic", "dm":
		return true
	default:
		return false
	}
}

func parseChannelMessagesPath(path string) (channelDocID string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 4 || parts[0] != "v1" || parts[1] != "channels" || parts[3] != "messages" {
		return "", false
	}
	if parts[2] == "" {
		return "", false
	}
	return parts[2], true
}

func parseTaskPath(path string) (taskDocID string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 3 || parts[0] != "v1" || parts[1] != "tasks" {
		return "", false
	}
	if parts[2] == "" {
		return "", false
	}
	return parts[2], true
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
