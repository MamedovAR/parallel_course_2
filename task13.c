#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <math.h>
#define IDX2F(i,j,ld) (((j)-1)*(ld))+((i)-1)
#define IDX2C(i,j,ld) (((j)*(ld))+(i))


int iter;

int main(int argc, char** argv){
	clock_t begin = clock();

	int size = atoi(argv[1]), iterlim = atoi(argv[2]);
	float exact = 0.000001, err = INT_MAX;

	float** arrprev;
	float** arrnew;

	//Array initialization
	arrprev = malloc(sizeof(float*) * size);
	arrnew = malloc(sizeof(float*) * size);
	for(int i = 0; i < size; i++){
		arrprev[i] = malloc(sizeof(float) * size);
		arrnew[i] = malloc(sizeof(float) * size);
	}

	//Initial computation
	int k = size - 1;
	float step = (float)10/size;
	arrprev[0][0] = 10;
	arrprev[0][k] = 20;
	arrprev[k][0] = 20;
	arrprev[k][k] = 30;
	for(int i = 1; i < size - 1; i++){
		arrprev[0][i] = arrprev[0][i - 1] + step;
		arrprev[k][i] = arrprev[k][i - 1] + step;
		arrprev[i][0] = arrprev[i - 1][0] + step;
		arrprev[i][k] = arrprev[i - 1][k] + step;
	}

	#pragma acc data copy(arrprev[:size][:size]) create(arrnew[:size][:size]) //Copy arrays to GPU
	{
	#pragma acc parallel loop
	for(int i = 0; i < size; i++){
		arrnew[0][i] = arrprev[0][i];
		arrnew[k][i] = arrprev[k][i];
		arrnew[i][0] = arrprev[i][0];
		arrnew[i][k] = arrprev[i][k];
	}

	while(iter <= iterlim && err > exact){
		iter++;
		err = 0;
		
		#pragma acc data present(arrprev, arrnew) //Update the pointers
		#pragma acc parallel loop gang worker num_workers(4) vector_length(128) //Optimization of computations
		for(int i = 1; i < size - 1; i++){
			#pragma acc loop vector reduction(max:err) //Maximization of the error on GPU
			for(int j = 1; j < size - 1; j++){
				arrnew[i][j] = 0.25 * (arrprev[i - 1][j] + arrprev[i + 1][j] + arrprev[i][j - 1] + arrprev[i][j + 1]);
				err = fmax(err, arrnew[i][j] - arrprev[i][j]);
			}
		}

		//Array swap
		float** temp = arrprev;
		arrprev = arrnew;
		arrnew = temp;

		//Print the results after every 1000 iterations
		if(iter % 1000 == 0 || iter == 1){
			printf("On %d iteration error equals %lf\n", iter, err);
			clock_t mid = clock();

			double te_mid = (double)(mid - begin) / CLOCKS_PER_SEC;
			printf("Time elapsed %lf\n", te_mid);
		}
	}
	}

	printf("On %d iteration error descended to %lf\n", iter, err);

	//Results
	for(int i = 0; i < size; i++){
		free(arrprev[i]);
		free(arrnew[i]);
	}
	free(arrprev);
	free(arrnew);

	clock_t end = clock();
	
	double te = (double)(end - begin) / CLOCKS_PER_SEC;
	printf("Time elapsed: %lf\n", te);

	return 0;
}
