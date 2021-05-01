#include "point_search.h"

SearchContext* create(const Point* points_begin, const Point* points_end) {
  SearchContext* sc = malloc(sizeof(SearchContext));
  sc->points = malloc((points_end - points_begin) * sizeof(Point));
  memcpy(sc->points, points_begin, (points_end - points_begin) * sizeof(Point));
  sc->points = sc->points;
  sc->points_len = (points_end - points_begin);
  /* for (int i = 0; i < sc->points_len; i++) { */
  /*   printf("x: %.2f, y: %.2f\n", sc->points[i].x, sc->points[i].y); */
  /* } */
  return sc;
}

int point_cmp(const void* lhs, const void* rhs) {
  return ((Point*)lhs)->rank - ((Point*)rhs)->rank;
}

bool point_in_rect(float x, float y, float lx, float ly, float hx, float hy) {
  /* printf("(%.2f, %.2f) inside of (%.2f, %.2f)b(%.2f, %.2f)\n", x, y, lx, ly, hx, hy); */
  return
    x > lx &&
    x < hx &&
    y > ly &&
    y < hy;
}

int32_t search(SearchContext* sc, const Rect rect, const int32_t count, Point* out_points) {
  /* printf("lx: %.2f, ly: %.2f hx: %.2f, hy: %.2f\n", rect.lx, rect.ly, rect.hx, rect.hy); */
  Point* temp_points = malloc(sizeof(Point) * sc->points_len);
  int out_count = 0;
  for (int i = 0; i < sc->points_len; i++) {
    if (point_in_rect(sc->points[i].x, sc->points[i].y, rect.lx, rect.ly, rect.hx, rect.hy)) {
      temp_points[out_count] = sc->points[i];
      out_count++;
    }
  }

  /* if (out_count > count) { */
  /*   printf("Too many points inside rect!\n"); */
  /* } */
  /* printf("out_count: %d\n", out_count); */
  qsort(temp_points, out_count, sizeof(Point), point_cmp);
  int copy_count = out_count < count ? out_count : count;
  /* if (copy_count != count) printf("Only found %d out of %d\n", copy_count, count); */
  memcpy(out_points, temp_points, sizeof(Point) * copy_count);
  free(temp_points);
  return copy_count;
}

SearchContext* destroy(SearchContext* sc) {
  free(sc->points);
  free(sc);
  return NULL;
}
