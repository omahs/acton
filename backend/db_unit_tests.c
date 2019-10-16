#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <assert.h>

#include "db.h"

typedef struct actor_collection_item {
	int actor_id;
	int collection_id;
	int item_id;
	int item_value;
} actor_collection_item_t;

int no_cols = 4;
int no_primary_keys = 1;
int no_clustering_keys = 2;
int no_index_keys = 1;

int no_actors = 2;
int no_collections = 2;
int no_items = 2;

// Create schema:

int create_schema(db_t * db, unsigned int * fastrandstate) {
	int primary_key_idx = 0;
	int clustering_key_idxs[2];
	clustering_key_idxs[0]=1;
	clustering_key_idxs[1]=2;
	int index_key_idx=3;

	int * col_types = (int *) malloc(no_cols * sizeof(int));

	for(int i=0;i<no_cols;i++)
		col_types[i] = DB_TYPE_INT32;

	db_schema_t* db_schema = db_create_schema(col_types, no_cols, &primary_key_idx, no_primary_keys, clustering_key_idxs, no_clustering_keys, &index_key_idx, no_index_keys);

	assert(db_schema != NULL && "Schema creation failed");

	// Create table:

	return db_create_table((WORD) 0, db_schema, db, fastrandstate);;
}

// Populate DB (also db_insert test):

int populate_db(db_t * db, unsigned int * fastrandstate) {
	for(long aid=0;aid<no_actors;aid++)
	{
		for(long cid=0;cid<no_collections;cid++)
		{
			for(long iid=0;iid<no_items;iid++)
			{
				WORD * column_values = (WORD *) malloc(no_cols * sizeof(WORD));

				column_values[0] = (WORD) aid;
				column_values[1] = (WORD) cid;
				column_values[2] = (WORD) iid;
				column_values[3] = (WORD) iid + 1;

				if(db_insert(column_values, no_cols, (WORD) 0, db, fastrandstate) != 0)
					return -1;
			}
		}
	}

	return 0;
}

// Read by (PK, CK1, CK2, Column):

int test_search_column(db_t * db) {
	int ret = 0;
	int column_idxs[no_cols];
	for(int i=0;i<no_cols;i++)
		column_idxs[i]=i;

	for(long aid=0;aid<no_actors;aid++)
	{
		for(long cid=0;cid<no_collections;cid++)
		{
			for(long iid=0;iid<no_items;iid++)
			{
				WORD * column_values = (WORD *) malloc(no_cols * sizeof(WORD));

				column_values[0] = (WORD) aid;
				column_values[1] = (WORD) cid;
				column_values[2] = (WORD) iid;
				column_values[3] = (WORD) iid + 1;

				WORD* col_values = db_search_columns(&column_values[0], &column_values[1], (int*) column_idxs, no_cols, (WORD) 0, db);

				for(int i=0;i<no_cols;i++)
				{
					if(col_values[i] != column_values[i])
					{
						printf("Read back mismatched column %d on row (%ld, %ld, %ld, %ld). Read back: (%ld, %ld, %ld, %ld)!\n",
								i, (long) column_values[0], (long) column_values[1], (long) column_values[2], (long) column_values[3],
								(long) col_values[0], (long) col_values[1], (long) col_values[2], (long) col_values[3]);
						ret = -1;
					}
				}
			}
		}
	}

	return ret;
}


// Read by (PK):

int test_search_pk(db_t * db)
{
	for(long aid=0;aid<no_actors;aid++)
	{
		db_row_t* row = db_search((WORD *) &aid, (WORD) 0, db);

		if((long) row->key != aid)
		{
			printf("Read back mismatched pk %ld ( != %ld)!\n", (long) row->key, aid);
			return -1;
		}
	}

	return 0;
}

// Read by (PK, CK1):

int test_search_pk_ck1(db_t * db)
{
	for(long aid=0;aid<no_actors;aid++)
	{
		for(long cid=0;cid<no_collections;cid++)
		{
			db_row_t* row = db_search_clustering((WORD *) &aid, (WORD *) &cid, 1, (WORD) 0, db);

			if((long) row->key != cid)
			{
				printf("Read back mismatched ck1 %ld ( != %ld) in cell (%ld, %ld)!\n", (long) row->key, cid, aid, cid);
				return -1;
			}
		}
	}

	return 0;
}

// Read by (PK, CK1, CK2):

int test_search_pk_ck1_ck2(db_t * db)
{
	for(long aid=0;aid<no_actors;aid++)
	{
		for(long cid=0;cid<no_collections;cid++)
		{
			for(long iid=0;iid<no_items;iid++)
			{
				WORD * cks = (WORD *) malloc(2 * sizeof(WORD));
				cks[0] = (WORD) cid;
				cks[1] = (WORD) iid;

				db_row_t* row = db_search_clustering((WORD *) &aid, cks, 2, (WORD) 0, db);

				if((long) row->key != iid)
				{
					printf("Read back mismatched ck2 %ld ( != %ld) in cell (%ld, %ld, %ld)!\n", (long) row->key, iid, aid, cid, iid);
					return -1;
				}
			}
		}
	}

	return 0;
}

// Read by secondary index:

int test_search_index(db_t * db)
{
	// TO DO: fix

	for(long iid=0;iid<no_items;iid++)
	{
		db_row_t* row = db_search_index((WORD) (iid + 1), 0, (WORD) 0, db);

		if(row == NULL)
		{
			printf("Read back mismatched row for secondary key %ld!\n", iid + 1);
			return -1;
		}
	}

	return 0;
}

// Update by (PK, CK1, CK2, Column):

int test_update(db_t * db)
{
	int ret = 0;
	int column_idxs[no_cols];
	for(int i=0;i<no_cols;i++)
		column_idxs[i]=i;

	for(long aid=0;aid<no_actors;aid++)
	{
		for(long cid=0;cid<no_collections;cid++)
		{
			for(long iid=0;iid<no_items;iid++)
			{
				WORD * column_values = (WORD *) malloc(no_cols * sizeof(WORD));

				column_values[0] = (WORD) aid;
				column_values[1] = (WORD) cid;
				column_values[2] = (WORD) iid;
				column_values[3] = (WORD) iid + 2;

				if(db_update(column_idxs, no_cols, column_values, (WORD) 0, db) != 0)
					return -2;

				WORD* col_values = db_search_columns(&column_values[0], &column_values[1], (int*) column_idxs, no_cols, (WORD) 0, db);

				for(int i=0;i<no_cols;i++)
				{
					if(col_values[i] != column_values[i])
					{
						printf("Read back mismatched column %d on row (%ld, %ld, %ld, %ld). Read back: (%ld, %ld, %ld, %ld)!\n",
								i, (long) column_values[0], (long) column_values[1], (long) column_values[2], (long) column_values[3],
								(long) col_values[0], (long) col_values[1], (long) col_values[2], (long) col_values[3]);
						ret = -1;
					}
				}
			}
		}
	}

	return ret;
}

// Delete by (PK):

int test_delete_pk(db_t * db)
{
	for(long aid=0;aid<no_actors;aid++)
	{
		if(db_delete_row((WORD *) &aid, (WORD) 0, db) != 0)
		{
			printf("Delete failed for pk %ld!\n", aid);
			return -1;
		}

		db_row_t* row = db_search((WORD *) &aid, (WORD) 0, db);

		if(row != NULL)
		{
			printf("Delete failed for pk %ld - did not delete row (return row key %ld)!\n", aid, (long) row->key);
			return -1;
		}
	}

	return 0;
}

// Delete by (PK, CK1):

int test_delete_pk_ck1(db_t * db)
{
	// TO DO:

	return 0;
}

// Delete by (PK, CK1, CK2):

int test_delete_pk_ck1_ck2(db_t * db)
{
	// TO DO:

	return 0;
}

// Delete by (PK, CK1, CK2, Column):

int test_delete_col(db_t * db)
{
	// TO DO:

	return 0;
}

// Delete by secondary index:
int test_delete_index(db_t * db)
{
	for(long iid=0;iid<no_items;iid++)
	{
		if(db_delete_by_index((WORD) (iid + 1), 0, (WORD) 0, db) != 0)
		{
			printf("Delete failed for secondary key value %ld!\n", iid + 1);
			return -1;
		}

		db_row_t* row = db_search_index((WORD) (iid + 1), 0, (WORD) 0, db);

		if(row != NULL)
		{
			printf("Delete failed for secondary key value %ld - did not delete row (return row key %ld)!\n", iid + 1, (long) row->key);
			return -1;
		}
	}

	return 0;
}

// Range search by PK:

int test_range_search_pk(db_t * db)
{
	// TO DO: Improve (check returned keys):

	long start_key = 0;
	long end_key = no_actors - 1;
	snode_t* start_row = NULL, * end_row = NULL;

	return (db_range_search((WORD*) &start_key, (WORD*) &end_key, &start_row, &end_row, (WORD) 0, db) == no_actors);
}

int test_range_search_pk_copy(db_t * db)
{
	// TO DO: Improve (check returned keys):

	long start_key = 0;
	long end_key = no_actors - 1;
	db_row_t* rows = NULL;

	return (db_range_search_copy((WORD*) &start_key, (WORD*) &end_key, &rows, (WORD) 0, db) == no_actors);
}

// Range search by (PK, CK1):

int test_range_search_pk_ck1(db_t * db)
{
	// TO DO: Improve (check returned keys):

	long pk = 0;
	long start_key = 0;
	long end_key = no_collections - 1;
	snode_t* start_row = NULL, * end_row = NULL;

	return (db_range_search_clustering((WORD*) &pk,(WORD*) &start_key, (WORD*) &end_key, 1, &start_row, &end_row, (WORD) 0, db) == no_collections);
}

// Range search by (PK, CK1, CK2):

int test_range_search_pk_ck1_ck2(db_t * db)
{
	// TO DO: Improve (check returned keys):

	long pk = 0;
	long start_keys[2];
	start_keys[0] = 0;
	start_keys[1] = 0;

	long end_keys[2];
	end_keys[0] = 0;
	end_keys[1] = no_items - 1;

	snode_t* start_row = NULL, * end_row = NULL;

	return (db_range_search_clustering((WORD*) &pk,(WORD*) start_keys, (WORD*) end_keys, 2, &start_row, &end_row, (WORD) 0, db) == no_collections);
}

// Range search by secondary index:

int test_range_search_index(db_t * db)
{
	// TO DO: Improve (check returned keys):

	long start_key = 1;
	long end_key = no_items;
	snode_t* start_row = NULL, * end_row = NULL;

	return (db_range_search_index(0, (WORD) start_key, (WORD) end_key, &start_row, &end_row, (WORD) 0, db) == no_items);
}


int main(int argc, char **argv) {
	unsigned int seed;
	int ret = 0;

	GET_RANDSEED(&seed, 0); // thread_id

	// Get db pointer:

	db_t * db = get_db();

	// Create schema:

	ret = create_schema(db, &seed);
	printf("Test %s - %s\n", "create_schema", ret==0?"OK":"FAILED");

	// Populate DB:

	ret = populate_db(db, &seed);
	printf("Test %s - %s\n", "populate_db", ret==0?"OK":"FAILED");

	// Read by (PK):

	ret = test_search_pk(db);
	printf("Test %s - %s\n", "test_search_pk", ret==0?"OK":"FAILED");

	// Read by (PK, CK1):

	ret = test_search_pk_ck1(db);
	printf("Test %s - %s\n", "test_search_pk_ck1", ret==0?"OK":"FAILED");

	// Read by (PK, CK1, CK2):

	ret = test_search_pk_ck1_ck2(db);
	printf("Test %s - %s\n", "test_search_pk_ck1_ck2", ret==0?"OK":"FAILED");

	// Read by (PK, CK1, CK2, Column):
	ret = test_search_column(db);
	printf("Test %s - %s\n", "test_search_column", ret==0?"OK":"FAILED");

	// Read by secondary index:

	ret = test_search_index(db);
	printf("Test %s - %s\n", "test_search_index", ret==0?"OK":"FAILED");

	// Update by (PK, CK1, CK2, Column):

	ret = test_update(db);
	printf("Test %s - %s\n", "test_update", ret==0?"OK":"FAILED");


	// Delete by (PK, CK1, CK2, Column):

	ret = test_delete_col(db);
	printf("Test %s - %s\n", "test_delete_col", ret==0?"OK":"FAILED");

	// Delete by (PK, CK1, CK2):

	ret = test_delete_pk_ck1_ck2(db);
	printf("Test %s - %s\n", "test_delete_pk_ck1_ck2", ret==0?"OK":"FAILED");

	// Delete by (PK, CK1):

	ret = test_delete_pk_ck1(db);
	printf("Test %s - %s\n", "test_delete_pk_ck1", ret==0?"OK":"FAILED");

	// Delete by (PK):

	ret = test_delete_pk(db);
	printf("Test %s - %s\n", "test_delete_pk", ret==0?"OK":"FAILED");

	ret = populate_db(db, &seed);
	printf("Test %s - %s\n", "repopulate_db", ret==0?"OK":"FAILED");

	// Delete by secondary index:

//	ret = test_delete_index(db);
//	printf("Test %s - %s\n", "", ret==0?"OK":"FAILED");

//	ret = populate_db(db, &seed);

	// Range search by PK:

	ret = test_range_search_pk(db);
	printf("Test %s - %s\n", "test_delete_index", ret==0?"OK":"FAILED");

	// Range search by PK (copy):

	ret = test_range_search_pk_copy(db);
	printf("Test %s - %s\n", "test_range_search_pk_copy", ret==0?"OK":"FAILED");

	// Range search by (PK, CK1):

	ret = test_range_search_pk_ck1(db);
	printf("Test %s - %s\n", "test_range_search_pk_ck1", ret==0?"OK":"FAILED");

	// Range search by (PK, CK1, CK2):

	ret = test_range_search_pk_ck1_ck2(db);
	printf("Test %s - %s\n", "test_range_search_pk_ck1_ck2", ret==0?"OK":"FAILED");

	// Range search by secondary index:

	ret = test_range_search_index(db);
	printf("Test %s - %s\n", "test_range_search_index", ret==0?"OK":"FAILED");

	return 0;
}



