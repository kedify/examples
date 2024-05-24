import { useQuery } from '@tanstack/react-query';
import { getAvailableImages } from './services/images';

export const useImagesQuery = () => {
  return useQuery({
    queryKey: ['images'],
    queryFn: () => getAvailableImages(),
    staleTime: 2000,
    refetchInterval: 2000,
  });
};
