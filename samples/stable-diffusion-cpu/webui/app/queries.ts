'use server';

import { useQuery } from '@tanstack/react-query';
import { getAvailableImages } from './services/images';

export const useImagesQuery = () => {
  return useQuery({
    queryKey: ['images'],
    queryFn: () => getAvailableImages(),
    staleTime: 1,
    refetchInterval: 1,
  });
};