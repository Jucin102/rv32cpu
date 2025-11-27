// Quick sort in C

// volatile unsigned char data[] = {8, 7, 2, 1, 0, 9, 6, 10, 16, 19, 22, -1, 75, -8, 89, 17, 52, -10, 102, 3, 4, 5, 1, 2, 3, 5, 1, 2, 3};
volatile unsigned char data[] = {1, 2, 5, 6, 7, 1, 2, 3, 6, 1, 1, 2, 3, 4, 5, 6, 7, 2, 3, 6, 3, 2, 2};

// function to swap elements
void swap(volatile unsigned char *a, volatile unsigned char *b) {
  volatile unsigned char t = *a;
  *a = *b;
  *b = t;
}

// function to find the partition position
unsigned char partition(volatile unsigned char array[], volatile unsigned char low, volatile unsigned char high) {
  
  // select the rightmost element as pivot
  volatile unsigned char pivot = array[high];
  
  // povolatile unsigned charer for greater element
  volatile unsigned char i = (low - 1);

  // traverse each element of the array
  // compare them with the pivot
  for (volatile unsigned char j = low; j < high; j++) {
    if (array[j] <= pivot) {
        
      // if element smaller than pivot is found
      // swap it with the greater element pointed by i
      i++;
      
      // swap element at i with element at j
      swap(&array[i], &array[j]);
    }
  }

  // swap the pivot element with the greater element at i
  swap(&array[i + 1], &array[high]);
  
  // return the partition point
  return (i + 1);
}

void quickSort(volatile unsigned char array[], volatile unsigned char low, volatile unsigned char high) {
  if (low < high) {
    
    // find the pivot element such that
    // elements smaller than pivot are on left of pivot
    // elements greater than pivot are on right of pivot
    volatile unsigned char pi = partition(array, low, high);
    
    // recursive call on the left of pivot
    quickSort(array, low, pi - 1);
    
    // recursive call on the right of pivot
    quickSort(array, pi + 1, high);
  }
}

// main function
unsigned char main() {
  
  volatile unsigned char n = sizeof(data) / sizeof(data[0]);
  
  // perform quicksort on data
  quickSort(data, 0, n - 1);
}