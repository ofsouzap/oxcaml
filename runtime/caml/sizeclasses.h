/* This file is generated by tools/gen_sizeclasses.ml */
#define POOL_WSIZE 4096
#define POOL_HEADER_WSIZE 7
#define SIZECLASS_MAX 128
#define NUM_SIZECLASSES 33

typedef unsigned char sizeclass_t;
static_assert(NUM_SIZECLASSES < (1 << (CHAR_BIT * sizeof(sizeclass_t))), "");

/* The largest size for this size class.
   (A gap is left after smaller objects) */
static const unsigned int wsize_sizeclass[NUM_SIZECLASSES] =
{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 17, 19, 22, 25, 28, 32, 33, 37,
  42, 47, 53, 59, 65, 73, 81, 89, 99, 108, 118, 128 };

/* The number of padding words to use, at the beginning of a pool
   of this sizeclass, to reach exactly POOL_WSIZE words. */
static const unsigned char wastage_sizeclass[NUM_SIZECLASSES] =
{ 0, 1, 0, 1, 4, 3, 1, 1, 3, 9, 9, 1, 9, 9, 4, 19, 14, 1, 25, 30, 19, 15, 0,
  8, 18, 59, 1, 39, 84, 30, 93, 77, 121 };

/* Map from (positive) object sizes to size classes. */
static const sizeclass_t sizeclass_wsize[SIZECLASS_MAX + 1] =
{ 255, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 14, 14, 15,
  15, 15, 16, 16, 16, 17, 17, 17, 18, 18, 18, 18, 19, 20, 20, 20, 20, 21, 21,
  21, 21, 21, 22, 22, 22, 22, 22, 23, 23, 23, 23, 23, 23, 24, 24, 24, 24, 24,
  24, 25, 25, 25, 25, 25, 25, 26, 26, 26, 26, 26, 26, 26, 26, 27, 27, 27, 27,
  27, 27, 27, 27, 28, 28, 28, 28, 28, 28, 28, 28, 29, 29, 29, 29, 29, 29, 29,
  29, 29, 29, 30, 30, 30, 30, 30, 30, 30, 30, 30, 31, 31, 31, 31, 31, 31, 31,
  31, 31, 31, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32 };
