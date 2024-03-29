#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <cub/cub.cuh>
#include <cub/block/block_load.cuh>
#include <cub/block/block_store.cuh>
#include <cub/block/block_reduce.cuh>
#define IDX2F(i,j,ld) (((j)-1)*(ld))+((i)-1)
#define IDX2C(i,j,ld) (((j)*(ld))+(i))
using namespace cub;
using namespace std;
__global__ void change(float* setka, float* arr, int s)
{
  int i = blockDim.x * blockIdx.x + threadIdx.x;
	int j = blockDim.y * blockIdx.y + threadIdx.y;
	if (i > 0 && j > 0 && i < s - 1 && j < s - 1){
		setka[IDX2C(i, j, s)] = 0.25 * (arr[IDX2C(i + 1, j, s)] + arr[IDX2C(i - 1, j, s)] + arr[IDX2C(i, j + 1, s)] + arr[IDX2C(i, j - 1, s)]);
	}
//	setka[IDX2C(i+threadIdx.x,j+threadIdx.y,s)]=0.25*(arr[IDX2C(i+threadIdx.x,j-1+threadIdx.y,s)]+arr[IDX2C(i+threadIdx.x,j+1+threadIdx.y,s)]+arr[IDX2C(i-1+threadIdx.x,j+threadIdx.y,s)]+arr[IDX2C(i+1+threadIdx.x,j+threadIdx.y,s)]);
}

__global__ void subtract_modulo_kernel(float* d_in1, float* d_in2, float* d_out, int size) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < size) {
        int diff = d_in1[idx] - d_in2[idx];
        d_out[idx] = fabs(diff);
    }
}

int main(int argc, char** argv)
{
  float a=0;
  int s=0;
  int n=0;
  if(argv[1][1]=='h')
  {
    printf("Put -h to show this.\n");
    printf("Put -a <NUMBER_OF_ACCURACY*10^6> -s <SIZE^2> -n <NUMBER_OF_ITERATION*10^6>.\n");
  }
  else
  {
    for(int k=1; k<argc; k+=2)
    {
      if(argv[k][1]=='a')
        a=(float)atof(argv[k+1]);
      else if(argv[k][1]=='s')
        s=atoi(argv[k+1]);
      else if(argv[k][1]=='n')
        n=atoi(argv[k+1]);
    }

    float* setka = (float*)calloc(s*s,sizeof(float));
    float* arr = (float*)calloc(s*s,sizeof(float));
    float* arr2 = (float*)calloc(s*s,sizeof(float));

    setka[0]=10;
    setka[s-1]=20;
    setka[(s-1)*s]=20;
    setka[s*s-1]=30;
    arr[0]=10;
    arr[s-1]=20;
    arr[(s-1)*s]=20;
    arr[s*s-1]=30;
    arr2[0]=10;
    arr2[s-1]=20;
    arr2[(s-1)*s]=20;
    arr2[s*s-1]=30;
    float l1=(10);
    l1/=s;
    float l2=20;
    l2/=s;
    int iter=0;
    float err=1;
    for(int i=1; i<s-1; i++)
    {
      setka[i]=setka[i-1]+l1;
      setka[i*s]+=setka[(i-1)*s]+l2;
      setka[s-1+i*s]+=setka[s-1+(i-1)*s]+l1;
      setka[s*(s-1)+i]+=setka[s*(s-1)+i-1]+l1;
      arr[i]=setka[i];
      arr[i*s]=setka[i*s];
      arr[s-1+i*s]=setka[s-1+i*s];
      arr[s*(s-1)+i]=setka[s*(s-1)+i];
    }

    if(s<16)
    {
      for(int i=0; i<s; i++)
      {
        for(int j=0; j<s; j++)
          printf("%f ",setka[i+s*j]);
        printf("\n");
      
      }
    }
    float *cusetka;
    float *cuarr;
    float* cuarr2;
    cudaMalloc((void**)&cusetka, s*s*sizeof(float));
    cudaMalloc((void**)&cuarr2, s*s*sizeof(float));
    cudaMalloc((void**)&cuarr, s*s*sizeof(float));
    cudaMemcpy(cuarr2, cuarr2, s*s*sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(cusetka, setka, s*s*sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(cuarr, arr, s*s*sizeof(float), cudaMemcpyHostToDevice);
    dim3 threadsPerBlock(8, 8);
    dim3 blocksPerGrid(n / threadsPerBlock.x + 1, n / threadsPerBlock.y + 1);
    while(err>a && iter<n)
    {
      iter++;
      if(iter%100==1)
        err=0;
      change<<<blocksPerGrid, threadsPerBlock >>>(cusetka, cuarr, n);
      change<<<blocksPerGrid, threadsPerBlock >>>(cuarr, cusetka, n);
      if(iter%100==1)
      {
        const int block_size = 256;
        const int num_blocks = (n + block_size - 1) / block_size;
        subtract_modulo_kernel<<<num_blocks, block_size>>>(cusetka, cuarr, arr2, n);

        cudaDeviceSynchronize();

        int max_value;
        void* d_temp_storage = nullptr;
        size_t temp_storage_bytes = 0;
        DeviceReduce::Max(d_temp_storage, temp_storage_bytes, arr2, &max_value, n);

        err=max_value;
        printf("%d %f\n", iter, err);
      }

      float* dop;
      dop = cuarr;
      cuarr=cusetka;
      cusetka = dop;
    }
    cudaMemcpy(setka,cusetka,s*s*sizeof(float),cudaMemcpyDeviceToHost);
    cudaMemcpy(arr, cuarr, s*s*sizeof(float), cudaMemcpyDeviceToHost);
    cudaFree(cusetka);
    cudaFree(cuarr);
    printf("Count iterations: %d\nError: %.10f\n", iter,err);
    if(s<16)
    {
      for(int i=0; i<s; i++)
      {
        for(int j=0; j<s; j++)
          printf("%f ",setka[i+s*j]);
        printf("\n");
      
      }
    }
    free(setka);
    free(arr);
  }
}