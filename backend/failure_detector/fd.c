/*
 * fd.c
 * Author: aagapi
 */

#include "fd.h"

gossip_state * init_gossip_state(int status, int node_id, int rack_id, int dc_id, vector_clock * vc)
{
	gossip_state * gs = (gossip_state *) malloc(sizeof(struct gossip_state));

	gs->status = status;
	gs->node_id = node_id;
	gs->rack_id = rack_id;
	gs->dc_id = dc_id;
	gs->vc = (vc != NULL)?vc:init_vc(0, NULL, NULL, 0);

	return gs;
}

void free_gossip_state(gossip_state * gs)
{
	free_vc(gs->vc);
	free(gs);
}

int serialize(gossip_state * gs, void ** buf, unsigned * len)
{
	GossipMessage msg = GOSSIPMESSAGE__INIT;

	VectorClockMessage vc_msg = VECTORCLOCKMESSAGE__INIT;
	init_vc_msg(&vc_msg, gs->vc);

	msg.vc = &vc_msg;
	msg.status = gs->status;
	msg.node_id = gs->node_id;
	msg.rack_id = gs->rack_id;
	msg.dc_id = gs->dc_id;

	*len = cmessage__get_packed_size (&msg);
	*buf = malloc (*len);
	cmessage__pack (&msg, *buf);

	free_vc_msg(&vc_msg);

	return 0;

}

int deserialize(void * buf, gossip_state ** gs)
{
	  size_t msg_len = read_buffer (MAX_MSG_SIZE_GS, (uint8_t *) buf);
	  GossipMessage * msg = cmessage__unpack(NULL, msg_len, buf);

	  if (msg == NULL)
	  { // Something failed
	    fprintf(stderr, "error unpacking gossip_state message\n");
	    return 1;
	  }

	  vector_clock * vc = init_vc_from_msg(msg->vc);

	  *gs = init_gossip_state(msg->status, msg->node_id, msg->rack_id, msg->dc_id, vc);

	  return 0;
}

